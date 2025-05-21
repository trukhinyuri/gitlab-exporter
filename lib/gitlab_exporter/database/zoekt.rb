module GitLab
  module Exporter
    module Database
      # A helper class to collect zoekt metrics.
      class ZoektCollector < Base
        QUERY = <<~SQL.freeze
          WITH task_counts AS (
            SELECT 
              zoekt_node_id,
              COUNT(*) AS count
            FROM 
              zoekt_tasks
            WHERE 
              perform_at <= $1
              AND state IN (0, 1)
            GROUP BY 
              zoekt_node_id
          )
          SELECT 
            n.id AS node_id,
            n.metadata ->> 'name' AS node_name,
            COALESCE(tc.count, 0) AS task_count
          FROM 
            zoekt_nodes n
          LEFT JOIN 
            task_counts tc ON n.id = tc.zoekt_node_id
        SQL

        ZOEKT_ENABLED_QUERY = <<~SQL.freeze
          SELECT
            zoekt_settings ->> 'zoekt_indexing_enabled' AS zoekt_indexing_enabled 
          FROM application_settings
          ORDER BY ID DESC
          LIMIT 1
        SQL

        def run
          return unless zoekt_indexing_enabled?

          execute(QUERY, [Time.now.utc])
        end

        private

        def zoekt_indexing_enabled?
          @zoekt_indexing_enabled ||=
            begin
              with_connection_pool do |conn|
                conn.exec(ZOEKT_ENABLED_QUERY).first["zoekt_indexing_enabled"] == "true"
              end
            rescue PG::UndefinedTable, PG::UndefinedColumn
              false
            end
        end

        def execute(query, params)
          with_connection_pool do |conn|
            conn.exec_params(query, params)
          end
        rescue PG::UndefinedTable, PG::UndefinedColumn
          nil
        end
      end

      # The prober which is called when gathering metrics
      class ZoektProber
        PrometheusMetrics.describe("search_zoekt_task_processing_queue_size",
                                   "Number of tasks waiting to be processed by Zoekt",
                                   "gauge")

        def initialize(metrics: PrometheusMetrics.new, **opts)
          @metrics = metrics
          @collector = opts[:collector] || ZoektCollector.new(**opts)
        end

        def probe_db
          results = @collector.run
          results.to_a.each do |row|
            @metrics.add(
              "search_zoekt_task_processing_queue_size",
              row["task_count"].to_i,
              node_name: row["node_name"],
              node_id: row["node_id"]
            )
          end

          self
        rescue PG::ConnectionBad
          self
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end
      end
    end
  end
end
