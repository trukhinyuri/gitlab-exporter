module GitLab
  module Monitor
    module Database
      # A helper class to collect dead tuples stats from the database
      #
      # It takes a connection string (e.g. "dbname=test port=5432")
      class DeadTuplesCollector < Base
        def run
          table_names = connection.exec("SELECT tablename FROM pg_tables WHERE tableowner = 'gitlab'").values.flatten
          stats       = {}

          table_names.each do |table_name|
            result = connection.exec("SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = '#{table_name}'")
            stats[table_name] = result[0]["n_dead_tup"].to_i
          end

          stats
        end
      end

      # Probes the DB specified by opts[:connection_string] for dead tubles stats, then converts them to metrics
      class DeadTuplesProber
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics   = metrics
          @collector = DeadTuplesCollector.new(connection_string: opts[:connection_string])
        end

        def probe_db
          return self unless @collector.connected?

          result = @collector.run

          result.each do |table_name, dead_tuples_count|
            @metrics.add("pg_dead_tuples", dead_tuples_count, table_name: table_name)
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
