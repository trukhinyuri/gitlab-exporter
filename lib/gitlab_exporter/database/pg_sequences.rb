module GitLab
  module Exporter
    module Database
      # A helper class to collect sequences metrics. Mainly used to monitor Cells sequences.
      class PgSequencesCollector < Base
        QUERY = <<~SQL.freeze
          SELECT
            schemaname,
            sequencename,
            CONCAT(schemaname, '.', sequencename) AS fully_qualified_sequencename,
            start_value,
            min_value,
            max_value,
            last_value AS current_value
          FROM pg_catalog.pg_sequences;
        SQL

        def run
          with_connection_pool do |conn|
            conn.exec(QUERY).each.with_object({}) do |row, stats|
              stats[row.delete("fully_qualified_sequencename")] = row
            end
          end
        end
      end

      # The prober which is called when gathering metrics
      class PgSequencesProber
        METRIC_NAME = "gitlab_pg_sequences".freeze
        METRIC_KEYS = %w[min_value max_value current_value].freeze

        def initialize(metrics: PrometheusMetrics.new, **opts)
          @metrics = metrics
          @collector = PgSequencesCollector.new(**opts)
        end

        def probe_db
          result = @collector.run

          result.each do |fully_qualified_sequencename, sequence_info|
            METRIC_KEYS.each do |key|
              value = sequence_info.fetch(key).to_f
              tags = {
                schemaname: sequence_info.fetch("schemaname"),
                sequencename: sequence_info.fetch("sequencename"),
                fully_qualified_sequencename: fully_qualified_sequencename
              }

              @metrics.add("#{METRIC_NAME}_#{key}", value, **tags)
            end
          end

          self
        rescue PG::ConnectionBad
          self
        end
      end
    end
  end
end
