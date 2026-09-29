module GitLab
  module Exporter
    module Database
      # A helper class to collect Geo node status metrics.
      class GeoNodeStatusCollector < Base
        QUERY = <<~SQL.freeze
          SELECT
            geo_node_statuses.geo_node_id,
            geo_nodes.name AS geo_node_name,
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
        TIMESTAMP_METRICS = %w[
          last_event_timestamp
          cursor_last_event_timestamp
          last_successful_status_check_timestamp
        ].freeze

        def initialize(metrics: PrometheusMetrics.new, **opts)
          @metrics = metrics
          @collector = opts[:collector] || GeoNodeStatusCollector.new(**opts)
        end

        def probe_db
          @collector.run.to_a.each do |row|
            labels = {
              geo_node_id: row["geo_node_id"],
              geo_node_name: row["geo_node_name"]
            }.compact

            row.fetch("status", {}).to_h.each do |name, value|
              add_metric(name, value, labels) if value.is_a?(Integer)
            end

            TIMESTAMP_METRICS.each do |name|
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
