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
  end
end
