module GitLab
  module Exporter
    module Database
      # A helper class to collect zoekt metrics.
      class ZoektCollector < Base
        # Query to get processing zoekt_tasks distribution by zoekt_node_id
        ZOEKT_TASKS_PROCESSING_QUERY = <<~SQL.freeze
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

        ZOEKT_NODES_QUERY = <<~SQL.freeze
          SELECT schema_version, id FROM zoekt_nodes
        SQL

        ZOEKT_REPOSITORY_SCHEMA_VERSION_QUERY = <<~SQL.freeze
          SELECT
            COUNT(*)
          FROM
            zoekt_repositories
          INNER JOIN
            zoekt_indices
            ON zoekt_repositories.zoekt_index_id = zoekt_indices.id
          WHERE
            zoekt_indices.zoekt_node_id = $1
            AND zoekt_repositories.schema_version < $2
            AND zoekt_repositories.state = 10;
        SQL

        ZOEKT_ENABLED_QUERY = <<~SQL.freeze
          SELECT
            zoekt_settings ->> 'zoekt_indexing_enabled' AS zoekt_indexing_enabled
          FROM application_settings
          ORDER BY ID DESC
          LIMIT 1
        SQL

        def run
          return {} unless zoekt_indexing_enabled?

          {
            task_processing_query_result: execute(ZOEKT_TASKS_PROCESSING_QUERY, [Time.now.utc]),
            repositories_schema_version_query_result: repositories_schema_version_query_result
          }.compact
        end

        private

        def repositories_schema_version_query_result
          hash = zoekt_node_schema_version_hash
          return if hash.nil?

          zoekt_repository_schema_version_result(hash)
        end

        def zoekt_node_schema_version_hash
          zoekt_nodes = execute(ZOEKT_NODES_QUERY)
          return if zoekt_nodes.nil?

          hash = {}
          zoekt_nodes.each do |row|
            hash[row["id"]] = row["schema_version"]
          end
          hash
        end

        def zoekt_repository_schema_version_result(hash)
          result = Set.new
          hash.each do |id, schema_version|
            query_result = execute(ZOEKT_REPOSITORY_SCHEMA_VERSION_QUERY, [id, schema_version])
            if query_result.nil?
              result = nil
              break
            end

            count = query_result[0]["count"].to_i
            result.add({ target_schema_version: schema_version, zoekt_node_id: id, unfinished_repository_count: count })
          end
          result
        end

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

        def execute(query, params = [])
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

        PrometheusMetrics.describe("search_zoekt_repositories_schema_version_count",
                                   "Number of zoekt_repositories which do not have the latest schema version",
                                   "gauge")

        def initialize(metrics: PrometheusMetrics.new, **opts)
          @metrics = metrics
          @collector = opts[:collector] || ZoektCollector.new(**opts)
        end

        def probe_db
          results = @collector.run
          results[:task_processing_query_result].to_a.each do |row|
            add_processing_zoekt_tasks_to_metric(row)
          end
          results[:repositories_schema_version_query_result]&.each do |row|
            add_zoekt_repositories_by_schema_version_to_metric(row)
          end

          self
        rescue PG::ConnectionBad
          self
        end

        def add_processing_zoekt_tasks_to_metric(row)
          @metrics.add(
            "search_zoekt_task_processing_queue_size",
            row["task_count"].to_i,
            node_name: row["node_name"],
            node_id: row["node_id"]
          )
        end

        def add_zoekt_repositories_by_schema_version_to_metric(row)
          @metrics.add(
            "search_zoekt_repositories_schema_version_count",
            row[:unfinished_repository_count].to_i,
            target_schema_version: row[:target_schema_version],
            zoekt_node_id: row[:zoekt_node_id]
          )
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end
      end
    end
  end
end
