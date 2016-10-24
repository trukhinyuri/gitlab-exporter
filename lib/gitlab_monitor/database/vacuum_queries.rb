module GitLab
  module Monitor
    module Database
      # A helper class to collect vacuum and vacuum analyze information
      #
      # It takes a connection string (e.g. "dbname=test port=5432")
      class VacuumQueriesCollector < Base
        def run
          stats = {}
          { vacuum: "VACUUM (?!ANALYZE)", vacuum_analyze: "VACUUM ANALYZE" }.each do |query_name, condition|
            result = connection.exec(
              <<-SQL
                SELECT COUNT(*) AS query_count, MAX(EXTRACT(EPOCH FROM (clock_timestamp() - query_start))) AS query_duration
                FROM pg_catalog.pg_stat_activity
                WHERE state = 'active' AND trim(query) ~* '\\A#{condition}';
              SQL
            )

            stats[query_name] = { "total" => result[0]["query_count"].to_i,
                                  "max_age" => result[0]["query_duration"].to_f }
          end

          stats
        end
      end

      # Probes the DB specified by opts[:connection_string] for vacuum and vacuum analyze information,
      # then converts them to metrics
      class VacuumQueriesProber
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics   = metrics
          @collector = VacuumQueriesCollector.new(connection_string: opts[:connection_string])
        end

        def probe_db
          return self unless @collector.connected?

          result = @collector.run

          @metrics.add("pg_vacuum_count", result[:vacuum]["total"])
          @metrics.add("pg_vacuum_age_in_seconds", result[:vacuum]["max_age"])
          @metrics.add("pg_vacuum_analyze_count", result[:vacuum_analyze]["total"])
          @metrics.add("pg_vacuum_analyze_age_in_seconds", result[:vacuum_analyze]["max_age"])

          self
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end
      end
    end
  end
end
