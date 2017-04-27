module GitLab
  module Monitor
    module Database
      # A helper class to collect queries stuck in idle in transaction
      #
      # It takes a connection string (e.g. "dbname=test port=5432")
      class StuckIdleInTransactionsCollector < Base
        def run
          result = connection.exec(
            <<-SQL
              SELECT COUNT(*) AS stuck_count
              FROM pg_stat_activity
              WHERE state = 'idle in transaction' AND (now() - query_start) > '10 minutes'::interval;
            SQL
          )

          result[0]["stuck_count"].to_i
        end
      end

      # Probes the DB specified by opts[:connection_string] for slow queries, then converts them to metrics
      class StuckIdleInTransactionsProber
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics   = metrics
          @collector = StuckIdleInTransactionsCollector.new(connection_string: opts[:connection_string])
        end

        def probe_db
          return self unless @collector.connected?

          @metrics.add("pg_stuck_idle_in_transactions_total", @collector.run)

          self
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end
      end
    end
  end
end
