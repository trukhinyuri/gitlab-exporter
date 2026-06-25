module GitLab
  module Exporter
    module Database
      # A helper class to collect zoekt metrics.
      # rubocop:disable Metrics/ClassLength
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
          SELECT schema_version, id, metadata ->> 'name' AS node_name FROM zoekt_nodes
        SQL

        ZOEKT_NODES_STATUS_QUERY = <<~SQL.freeze
          SELECT id, metadata ->> 'name' AS node_name,
            CASE
              WHEN last_seen_at < NOW() - INTERVAL '2 minute' THEN 0
              ELSE 1
            END AS status
          FROM zoekt_nodes;
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

        # unclaimed_storage_bytes and storage_percent_used are not real columns on
        # zoekt_nodes; they are derived in Search::Zoekt::Node. We compute them in SQL
        # here to avoid loading every row through ActiveRecord.
        ZOEKT_NODE_STORAGE_QUERY = <<~SQL.freeze
          SELECT
            zn.id,
            zn.metadata ->> 'name' AS node_name,
            (zn.usable_storage_bytes - COALESCE(zi.reserved_total, 0))::bigint
              AS unclaimed_storage_bytes,
            CASE
              WHEN zn.total_bytes > 0
                THEN zn.used_bytes::float8 / zn.total_bytes::float8
              ELSE 0
            END AS storage_percent_used
          FROM zoekt_nodes zn
          LEFT JOIN (
            SELECT zoekt_node_id, SUM(reserved_storage_bytes) AS reserved_total
            FROM zoekt_indices
            GROUP BY zoekt_node_id
          ) zi ON zi.zoekt_node_id = zn.id
        SQL

        ZOEKT_REPOSITORIES_STATE_QUERY = <<~SQL.freeze
          SELECT state, COUNT(*) FROM zoekt_repositories GROUP BY state
        SQL

        ZOEKT_INDICES_STATE_QUERY = <<~SQL.freeze
          SELECT state, COUNT(*) FROM zoekt_indices GROUP BY state
        SQL

        ZOEKT_INDICES_WATERMARK_QUERY = <<~SQL.freeze
          SELECT watermark_level, COUNT(*) FROM zoekt_indices GROUP BY watermark_level
        SQL

        ZOEKT_INDICES_STORAGE_QUERY = <<~SQL.freeze
          SELECT
            zoekt_indices.id,
            zoekt_indices.reserved_storage_bytes,
            zoekt_indices.used_storage_bytes,
            zoekt_nodes.metadata ->> 'name' AS node_name
          FROM
            zoekt_indices
          INNER JOIN
            zoekt_nodes ON zoekt_indices.zoekt_node_id = zoekt_nodes.id
        SQL

        ZOEKT_NODE_ENABLED_NAMESPACES_QUERY = <<~SQL.freeze
          SELECT
            zn.id AS node_id,
            zn.metadata ->> 'name' AS node_name,
            COUNT(DISTINCT zi.zoekt_enabled_namespace_id) AS count
          FROM zoekt_nodes zn
          LEFT JOIN zoekt_indices zi ON zi.zoekt_node_id = zn.id
          GROUP BY zn.id, zn.metadata ->> 'name'
        SQL

        ZOEKT_NODE_TASKS_QUERY = <<~SQL.freeze
          SELECT
            zn.id AS node_id,
            zn.metadata ->> 'name' AS node_name,
            zt.state,
            COUNT(*) AS count
          FROM zoekt_nodes zn
          LEFT JOIN zoekt_tasks zt ON zt.zoekt_node_id = zn.id
          GROUP BY zn.id, zn.metadata ->> 'name', zt.state
        SQL

        ZOEKT_INDICES_STALE_USED_STORAGE_QUERY = <<~SQL.freeze
          SELECT COUNT(*) AS count FROM zoekt_indices WHERE last_indexed_at >= used_storage_bytes_updated_at
        SQL

        ZOEKT_TASK_STATES = {
          0 => "pending",
          1 => "processing",
          10 => "done",
          250 => "skipped",
          255 => "failed",
          256 => "orphaned"
        }.freeze

        def run
          return {} unless zoekt_indexing_enabled?

          {
            task_processing_query_result: execute(ZOEKT_TASKS_PROCESSING_QUERY, [Time.now.utc]),
            repositories_schema_version_query_result: repositories_schema_version_query_result,
            zoekt_nodes_status_query_result: execute(ZOEKT_NODES_STATUS_QUERY),
            node_storage_query_result: execute(ZOEKT_NODE_STORAGE_QUERY),
            repositories_state_query_result: execute(ZOEKT_REPOSITORIES_STATE_QUERY),
            indices_state_query_result: execute(ZOEKT_INDICES_STATE_QUERY),
            indices_watermark_query_result: execute(ZOEKT_INDICES_WATERMARK_QUERY),
            indices_storage_query_result: execute(ZOEKT_INDICES_STORAGE_QUERY),
            node_enabled_namespaces_query_result: execute(ZOEKT_NODE_ENABLED_NAMESPACES_QUERY),
            node_tasks_query_result: execute(ZOEKT_NODE_TASKS_QUERY),
            indices_stale_used_storage_query_result: execute(ZOEKT_INDICES_STALE_USED_STORAGE_QUERY)
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
            hash[row["id"]] = [row["schema_version"], row["node_name"]]
          end
          hash
        end

        def zoekt_repository_schema_version_result(hash)
          result = Set.new
          hash.each do |id, schema_version_name_arr|
            query_result = execute(ZOEKT_REPOSITORY_SCHEMA_VERSION_QUERY, [id, schema_version_name_arr[0]])
            if query_result.nil?
              result = nil
              break
            end
            result.add(
              {
                target_schema_version: schema_version_name_arr[0], zoekt_node_id: id,
                zoekt_node_name: schema_version_name_arr[1], unfinished_repository_count: query_result[0]["count"].to_i
              }
            )
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
        rescue PG::UndefinedTable, PG::UndefinedColumn => e
          @logger&.warn("ZoektCollector query failed: #{e.class}: #{e.message.lines.first&.strip}")
          nil
        end
      end
      # rubocop:enable Metrics/ClassLength

      # The prober which is called when gathering metrics
      # rubocop:disable Metrics/ClassLength
      class ZoektProber
        PrometheusMetrics.describe(
          "search_zoekt_task_processing_queue_size",
          "Number of tasks waiting to be processed by Zoekt",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_repositories_schema_version_count",
          "Number of zoekt_repositories which do not have the latest schema version",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_nodes_status",
          "Status of each zoekt_node. 0 is offline (last seen more than 2 minutes ago), 1 is online",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_node_unclaimed_storage_bytes",
          "Unclaimed storage bytes for Zoekt node",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_node_storage_percent_used",
          "Fraction of storage used on Zoekt node (0..1)",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_repositories_states_total",
          "Number of Zoekt repositories in each state",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_indices_states",
          "Number of Zoekt indices in each state",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_indices_watermark_levels",
          "Number of Zoekt indices in each watermark level",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_indices_reserved_storage_bytes",
          "Reserved storage bytes for each Zoekt index",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_indices_used_storage_bytes",
          "Used storage bytes for each Zoekt index",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_node_enabled_namespaces",
          "Number of enabled namespaces per Zoekt node",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_node_tasks",
          "Number of Zoekt indexing tasks on a node, broken down by state",
          "gauge"
        )

        PrometheusMetrics.describe(
          "search_zoekt_indices_with_stale_used_storage_bytes",
          "Number of Zoekt indices whose used_storage_bytes value has not been updated since the last index run",
          "gauge"
        )

        def initialize(metrics: PrometheusMetrics.new, **opts)
          @metrics = metrics
          @collector = opts[:collector] || ZoektCollector.new(**opts)
        end

        def probe_db
          results = @collector.run
          process_results(results)
          self
        rescue PG::ConnectionBad
          self
        end

        private

        def process_results(results)
          process_task_results(results[:task_processing_query_result])
          process_repository_results(results[:repositories_schema_version_query_result])
          process_node_status_results(results[:zoekt_nodes_status_query_result])
          process_node_storage_results(results[:node_storage_query_result])
          process_repositories_state_results(results[:repositories_state_query_result])
          process_indices_state_results(results[:indices_state_query_result])
          process_indices_watermark_results(results[:indices_watermark_query_result])
          process_indices_storage_results(results[:indices_storage_query_result])
          process_node_enabled_namespaces_results(results[:node_enabled_namespaces_query_result])
          process_node_tasks_results(results[:node_tasks_query_result])
          process_indices_stale_used_storage_results(results[:indices_stale_used_storage_query_result])
        end

        def process_task_results(results)
          results.to_a.each { |row| add_processing_zoekt_tasks_to_metric(row) }
        end

        def process_repository_results(results)
          results&.each { |row| add_zoekt_repositories_by_schema_version_to_metric(row) }
        end

        def process_node_status_results(results)
          results&.each { |row| add_zoekt_nodes_status_to_metric(row) }
        end

        def process_node_storage_results(results)
          results&.each do |row|
            add_zoekt_node_unclaimed_storage_to_metric(row)
            add_zoekt_node_storage_percent_used_to_metric(row)
          end
        end

        def process_repositories_state_results(results)
          results&.each { |row| add_zoekt_repositories_state_to_metric(row) }
        end

        def process_indices_state_results(results)
          results&.each { |row| add_zoekt_indices_state_to_metric(row) }
        end

        def process_indices_watermark_results(results)
          results&.each { |row| add_zoekt_indices_watermark_to_metric(row) }
        end

        def process_indices_storage_results(results)
          results&.each { |row| add_zoekt_indices_storage_to_metric(row) }
        end

        def add_processing_zoekt_tasks_to_metric(row)
          @metrics.add(
            "search_zoekt_task_processing_queue_size",
            row["task_count"].to_i,
            **{
              node_name: row["node_name"],
              node_id: row["node_id"]
            }.compact
          )
        end

        def add_zoekt_repositories_by_schema_version_to_metric(row)
          @metrics.add(
            "search_zoekt_repositories_schema_version_count",
            row[:unfinished_repository_count].to_i,
            **{
              target_schema_version: row[:target_schema_version],
              zoekt_node_id: row[:zoekt_node_id],
              zoekt_node_name: row[:zoekt_node_name]
            }.compact
          )
        end

        def add_zoekt_nodes_status_to_metric(row)
          @metrics.add(
            "search_zoekt_nodes_status",
            row["status"].to_i,
            **{
              zoekt_node_id: row["id"],
              zoekt_node_name: row["node_name"]
            }.compact
          )
        end

        def add_zoekt_node_unclaimed_storage_to_metric(row)
          @metrics.add(
            "search_zoekt_node_unclaimed_storage_bytes",
            row["unclaimed_storage_bytes"].to_i,
            **{
              zoekt_node_id: row["id"],
              zoekt_node_name: row["node_name"]
            }.compact
          )
        end

        def add_zoekt_node_storage_percent_used_to_metric(row)
          @metrics.add(
            "search_zoekt_node_storage_percent_used",
            row["storage_percent_used"].to_f,
            **{
              zoekt_node_id: row["id"],
              zoekt_node_name: row["node_name"]
            }.compact
          )
        end

        def add_zoekt_repositories_state_to_metric(row)
          @metrics.add("search_zoekt_repositories_states_total", row["count"].to_i, **{ state: row["state"] }.compact)
        end

        def add_zoekt_indices_state_to_metric(row)
          @metrics.add("search_zoekt_indices_states", row["count"].to_i, **{ state: row["state"] }.compact)
        end

        def add_zoekt_indices_watermark_to_metric(row)
          @metrics.add(
            "search_zoekt_indices_watermark_levels",
            row["count"].to_i,
            **{
              watermark_level: row["watermark_level"]
            }.compact
          )
        end

        def process_node_enabled_namespaces_results(results)
          results&.each { |row| add_zoekt_node_enabled_namespaces_to_metric(row) }
        end

        def process_node_tasks_results(results)
          results&.each { |row| add_zoekt_node_tasks_to_metric(row) }
        end

        def process_indices_stale_used_storage_results(results)
          results&.each { |row| add_zoekt_indices_stale_used_storage_to_metric(row) }
        end

        def add_zoekt_node_enabled_namespaces_to_metric(row)
          @metrics.add(
            "search_zoekt_node_enabled_namespaces",
            row["count"].to_i,
            **{
              node_id: row["node_id"],
              node_name: row["node_name"]
            }.compact
          )
        end

        def add_zoekt_node_tasks_to_metric(row)
          state_int = row["state"]&.to_i
          return if row["state"].nil?

          state_label = ZoektCollector::ZOEKT_TASK_STATES[state_int]
          return if state_label.nil?

          @metrics.add(
            "search_zoekt_node_tasks",
            row["count"].to_i,
            **{
              node_id: row["node_id"],
              node_name: row["node_name"],
              state: state_label
            }.compact
          )
        end

        def add_zoekt_indices_stale_used_storage_to_metric(row)
          @metrics.add("search_zoekt_indices_with_stale_used_storage_bytes", row["count"].to_i)
        end

        def add_zoekt_indices_storage_to_metric(row)
          payload = { zoekt_index_id: row["id"], zoekt_node_name: row["node_name"] }.compact
          @metrics.add("search_zoekt_indices_reserved_storage_bytes", row["reserved_storage_bytes"].to_i, **payload)
          @metrics.add("search_zoekt_indices_used_storage_bytes", row["used_storage_bytes"].to_i, **payload)
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
