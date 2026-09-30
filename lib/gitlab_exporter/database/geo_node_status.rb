module GitLab
  module Exporter
    module Database
      # A helper class to collect Geo node status metrics.
      class GeoNodeStatusCollector < Base
        QUERY = <<~SQL.freeze
          SELECT
            geo_nodes.name AS geo_node_name,
            geo_node_statuses.db_replication_lag_seconds,
            geo_node_statuses.replication_slots_count,
            geo_node_statuses.replication_slots_used_count,
            geo_node_statuses.replication_slots_max_retained_wal_bytes,
            geo_node_statuses.last_event_id,
            geo_node_statuses.cursor_last_event_id,
            geo_node_statuses.status,
            EXTRACT(EPOCH FROM geo_node_statuses.last_event_date)::bigint AS last_event_timestamp,
            EXTRACT(EPOCH FROM geo_node_statuses.cursor_last_event_date)::bigint AS cursor_last_event_timestamp,
            EXTRACT(EPOCH FROM geo_node_statuses.last_successful_status_check_at)::bigint
              AS last_successful_status_check_timestamp
          FROM geo_node_statuses
          INNER JOIN geo_nodes ON geo_nodes.id = geo_node_statuses.geo_node_id
          WHERE geo_nodes.enabled = TRUE
        SQL

        def run
          with_connection_pool do |conn|
            conn.exec(QUERY)
          end
        rescue PG::UndefinedTable, PG::UndefinedColumn
          nil
        end
      end

      # The prober which is called when gathering metrics.
      class GeoNodeStatusProber
        METRIC_PREFIX = "geo_".freeze
        COUNT_SUFFIX = /_(count|total)\z/
        METRIC_ALIASES = { "project_repositories_count" => "repositories_count" }.freeze
        COLUMN_METRICS = %w[
          db_replication_lag_seconds
          replication_slots_count
          replication_slots_used_count
          replication_slots_max_retained_wal_bytes
          last_event_id
          cursor_last_event_id
        ].freeze
        TIMESTAMP_METRICS = %w[
          last_event_timestamp
          cursor_last_event_timestamp
          last_successful_status_check_timestamp
        ].freeze
        REPLICATOR_METRIC_SUFFIXES = %w[
          _count
          _checksum_total_count
          _checksummed_count
          _checksum_failed_count
          _synced_count
          _failed_count
          _registry_count
          _verification_total_count
          _verified_count
          _verification_failed_count
          _oldest_unsynced_time
        ].freeze
        NON_PROMETHEUS_STATUS_FIELDS = %w[projects_count].freeze

        def initialize(metrics: PrometheusMetrics.new, **opts)
          @metrics = metrics
          @collector = opts[:collector] || GeoNodeStatusCollector.new(**opts)
        end

        def probe_db
          @collector.run.to_a.each do |row|
            labels = {
              name: row["geo_node_name"],
              url: row["geo_node_name"]
            }

            row.fetch("status", {}).to_h.each do |name, value|
              add_metric(name, value, labels) if value.is_a?(Integer) && prometheus_metric?(name)
            end

            (COLUMN_METRICS + TIMESTAMP_METRICS).each do |name|
              add_metric(name, row[name], labels) if row[name].is_a?(Integer)
            end
          end

          self
        rescue PG::ConnectionBad
          self
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end

        private

        def prometheus_metric?(name)
          name = name.to_s
          return false if NON_PROMETHEUS_STATUS_FIELDS.include?(name)
          return false if COLUMN_METRICS.include?(name)

          REPLICATOR_METRIC_SUFFIXES.any? { |suffix| name.end_with?(suffix) }
        end

        def add_metric(name, value, labels)
          name = METRIC_ALIASES.fetch(name.to_s, name.to_s)
          metric_name = "#{METRIC_PREFIX}#{name.sub(COUNT_SUFFIX, '')}"
          PrometheusMetrics.describe(metric_name, "Geo node status metric", "gauge")
          @metrics.add(metric_name, value, **labels)
        end
      end
    end
  end
end
