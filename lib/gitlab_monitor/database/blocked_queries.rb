module GitLab
  module Monitor
    module Database
      # A helper class to collect blocked queries
      #
      # It takes a connection string (e.g. "dbname=test port=5432")
      class BlockedQueriesCollector < Base
        def run
          stats  = Hash.new(0)
          result = connection.exec(
            <<-SQL
              SELECT blocked.relation::regclass
              FROM pg_catalog.pg_locks blocked
              WHERE NOT blocked.granted
            SQL
          ).to_a

          result.each do |row|
            stats[row["relation"] || "__transaction__"] += 1
          end

          stats
        end
      end

      # Probes the DB specified by opts[:connection_string] for blocked queries, then converts them to metrics
      class BlockedQueriesProber
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics   = metrics
          @collector = BlockedQueriesCollector.new(connection_string: opts[:connection_string])
        end

        def probe_db
          return self unless @collector.connected?

          result = @collector.run

          result.each do |table_name, blocked_count|
            @metrics.add("pg_blocked_queries_total", blocked_count, table_name: table_name)
          end

          self
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end
      end
    end
  end
end
