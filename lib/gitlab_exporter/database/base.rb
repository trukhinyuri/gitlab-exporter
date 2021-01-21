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
          @@connection_pool ||= Hash.new do |h, connection_string| # rubocop:disable Style/ClassVars
            h[connection_string] = ConnectionPool.new(size: 3, timeout: 5) do
              PG.connect(connection_string).tap do |conn|
                configure_type_map_for_results(conn)
              end
            end
          end
        end

        def self.configure_type_map_for_results(conn)
          tm = PG::BasicTypeMapForResults.new(conn)

          # Remove warning message:
          # Warning: no type cast defined for type "name" with oid 19.
          # Please cast this type explicitly to TEXT to be safe for future changes.
          # Warning: no type cast defined for type "regproc" with oid 24.
          # Please cast this type explicitly to TEXT to be safe for future changes.
          [{ "type": "text", "oid": 19 }, { "type": "int4", "oid": 24 }].each do |value|
            old_coder = tm.coders.find { |c| c.name == value[:type] }
            tm.add_coder(old_coder.dup.tap { |c| c.oid = value[:oid] })
          end

          conn.type_map_for_results = tm
        end

        def initialize(args, logger: nil)
          @connection_string = args[:connection_string]
          @logger = logger
        end

        def run
          fail NotImplemented
        end

        def connection_pool
          self.class.connection_pool[@connection_string]
        end

        def with_connection_pool
          connection_pool.with do |conn|
            yield conn
          rescue PG::UnableToSend => e
            @logger.warn "Error sending to the database: #{e}" if @logger
            conn.reset
            raise e
          end
        rescue PG::Error => e
          @logger.error "Error connecting to the database: #{e}" if @logger
          raise e
        end
      end
    end
  end
end
