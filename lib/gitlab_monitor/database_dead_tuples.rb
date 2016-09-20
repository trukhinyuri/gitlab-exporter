require "pg"

module GitLab
  module Monitor
    # A helper class to collect dead tuples stats from the database
    #
    # It takes a connection string (e.g. "dbname=test port=5432")
    class DatabaseDeadTuplesCollector
      attr_reader :result

      def initialize(args)
        @connection_string = args[:connection_string]
      end

      def run
        table_names = connection.exec("SELECT tablename FROM pg_tables WHERE tableowner = 'gitlab'").values.flatten
        stats       = {}

        table_names.each do |table_name|
          result = connection.exec("SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = '#{table_name}'")
          stats[table_name] = result[0]["n_dead_tup"].to_i
        end

        stats
      end

      private

      def connection
        @connection ||= PG.connect(@connection_string)
      end
    end

    # Probes the DB specified by opts[:connection_string] for dead tubles stats, then converts them to metrics
    class DatabaseDeadTuplesProber
      def initialize(opts, metrics = PrometheusMetrics.new)
        @metrics   = metrics
        @collector = DatabaseDeadTuplesCollector.new(connection_string: opts[:connection_string])
      end

      def probe_db
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
