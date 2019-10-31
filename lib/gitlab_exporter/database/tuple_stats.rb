module GitLab
  module Exporter
    module Database
      # A helper class to collect tuple stats from the database
      #
      # It takes a connection string (e.g. "dbname=test port=5432")
      class TupleStatsCollector < Base
        COLUMNS = %w(relname seq_tup_read idx_tup_fetch n_tup_ins n_tup_upd n_tup_del n_tup_hot_upd n_dead_tup seq_scan)
                  .join(",")
        QUERY   = <<-SQL.freeze
          SELECT #{COLUMNS}
          FROM pg_stat_user_tables
          WHERE relname IN (SELECT tablename FROM pg_tables WHERE tableowner = 'gitlab')
          GROUP BY #{COLUMNS}
        SQL

        def run
          with_connection_pool do |conn|
            conn.exec(QUERY).each.with_object({}) do |row, stats|
              stats[row.delete("relname")] = row
            end
          end
        end
      end

      # Probes the DB specified by opts[:connection_string] for tuple stats, then converts them to metrics
      class TuplesProber
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics   = metrics
          @collector = TupleStatsCollector.new(connection_string: opts[:connection_string])
        end

        def probe_db
          result = @collector.run

          result.each do |table_name, tuple_stats|
            tuple_stats.each do |column_name, value|
              @metrics.add("gitlab_database_stat_table_#{column_name}",
                           value.to_f,
                           table_name: table_name) unless value.is_a?(Numeric)
            end
          end

          self
        rescue PG::ConnectionBad
          self
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end
      end
    end
  end
end
