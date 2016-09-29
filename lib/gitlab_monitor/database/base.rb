require "pg"

module GitLab
  module Monitor
    module Database
      # An abstract class for interacting with DB
      #
      # It takes a connection string (e.g. "dbname=test port=5432")
      class Base
        def initialize(args)
          @connection_string = args[:connection_string]
        end

        def run
          fail NotImplemented
        end

        def connected?
          !connection.nil?
        end

        private

        def connection
          @connection ||= PG.connect(@connection_string)
        rescue PG::ConnectionBad # rubocop:disable Lint/HandleExceptions
          # Do nothing, we could be on the slave machine
        end
      end
    end
  end
end
