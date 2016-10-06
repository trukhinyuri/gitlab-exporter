module GitLab
  module Monitor
    module Database
      # A helper class to collect slow queries
      #
      # It takes a connection string (e.g. "dbname=test port=5432")
      class SlowQueriesCollector < Base
        def run
          result = connection.exec(
            <<-SQL
              SELECT COUNT(*) AS slow_count
              FROM pg_stat_activity
              WHERE state = 'active' AND (now() - query_start) > '1 seconds'::interval;
            SQL
          )

          result[0]["slow_count"].to_i
        end
      end

      # Probes the DB specified by opts[:connection_string] for slow queries, then converts them to metrics
      class SlowQueriesProber
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics   = metrics
          @collector = SlowQueriesCollector.new(connection_string: opts[:connection_string])
        end

        def probe_db
          return self unless @collector.connected?

          @metrics.add("pg_slow_queries_total", @collector.run)

          self
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end
      end
    end
  end
end
