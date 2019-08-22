require "pg"
require "connection_pool"

module GitLab
  module Exporter
    module Database
      # An abstract class for interacting with DB
      #
      # It takes a connection string (e.g. "dbname=test port=5432")
      class Base
        def self.connection_pool
          @connection_pool ||= Hash.new do |h, connection_string|
            h[connection_string] = ConnectionPool.new(size: 3, timeout: 5) do
              PG.connect(connection_string)
            end
          end
        end

        def initialize(args)
          @connection_string = args[:connection_string]
        end

        def run
          fail NotImplemented
        end

        def connection_pool
          self.class.connection_pool[@connection_string]
        end

        def with_connection_pool
          connection_pool.with do |conn|
            begin
              yield conn
            rescue PG::UnableToSend => e
              conn.reset
              raise e
            end
          end
        end
      end
    end
  end
end
