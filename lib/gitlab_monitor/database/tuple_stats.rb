module GitLab
  module Monitor
    module Database
      # A helper class to collect tuple stats from the database
      #
      # It takes a connection string (e.g. "dbname=test port=5432")
      class TupleStatsCollector < Base
        def run
          table_names = connection.exec("SELECT tablename FROM pg_tables WHERE tableowner = 'gitlab'").values.flatten
          stats       = {}

          table_names.each do |table_name|
            result = connection.exec(
              <<-SQL
                SELECT seq_tup_read, idx_tup_fetch, n_tup_ins, n_tup_upd, n_tup_del, n_tup_hot_upd, n_dead_tup
                FROM pg_stat_user_tables
                WHERE relname = '#{table_name}'
              SQL
            )
            next if result.count.zero?

            stats[table_name] = result[0]
          end

          stats
        end
      end

      # Probes the DB specified by opts[:connection_string] for tuple stats, then converts them to metrics
      class TuplesProber
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics   = metrics
          @collector = TupleStatsCollector.new(connection_string: opts[:connection_string])
        end

        def probe_db
          return self unless @collector.connected?

          result = @collector.run

          result.each do |table_name, tuple_stats|
            tuple_stats.each do |column_name, value|
              @metrics.add("pg_stat_table_#{column_name}", value.to_s, table_name: table_name)
            end
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
