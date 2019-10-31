module GitLab
  module Exporter
    module Database
      # Helper to collect bloat metrics.
      class BloatCollector < Base
        def run(type = :btree)
          execute(self.class.query_for(type)).each_with_object({}) do |row, h|
            h[row["object_name"]] = row
          end
        end

        private

        def execute(query)
          with_connection_pool do |conn|
            conn.exec(query)
          end
        end

        class << self
          def query_for(type)
            @queries ||= {}

            return @queries[type] if @queries[type]

            file = File.join(__dir__, "bloat_#{type}.sql")
            fail "Unknown bloat query file: #{file}" unless File.exist?(file)

            @queries[type] = File.read(file)
          end
        end
      end

      # Prober class to gather bloat metrics
      class BloatProber
        METRIC_KEYS = %w(bloat_ratio bloat_size extra_size real_size).freeze

        attr_reader :metrics, :collector, :bloat_types

        def initialize(opts,
                       metrics: PrometheusMetrics.new,
                       collector: BloatCollector.new(connection_string: opts[:connection_string]))
          @metrics = metrics
          @collector = collector
          @bloat_types = opts[:bloat_types] || %i(btree table)
        end

        def probe_db
          bloat_types.each do |type|
            probe_for_type(type)
          end
        end

        def write_to(target)
          target.write(metrics.to_s)
        end

        private

        def probe_for_type(type)
          collector.run(type).each do |query_name, data|
            METRIC_KEYS.each do |key|
              metrics.add("gitlab_database_bloat_#{type}_#{key}", data[key].to_f, query_name: query_name)
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
