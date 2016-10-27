require "yaml"

module GitLab
  module Monitor
    # Stores runner classes in a single place
    #
    # The entry point is the module method "for" which takes the name of a runner.
    # In case the runner is invalid it will return a NullRunner which fails with an
    # InvalidCLICommand error, which contains the general application usage instructions.
    module CLI
      EXECUTABLE_NAME = "gitlab-mon".freeze

      def self.for(name)
        commands.fetch(name, NullRunner)
      end

      class InvalidCLICommand < RuntimeError; end

      # Empty runner that will raise an InvalidCLICommand when executed to provide the usage
      # in the exception message
      class NullRunner
        def initialize(args)
        end

        def run
          fail InvalidCLICommand.new("Usage: #{EXECUTABLE_NAME} <command> [options] [arguments...]\n\n"\
                                     "Available commands are: #{GitLab::Monitor::CLI.commands.keys.join(', ')}")
        end
      end

      # Git runner.
      #
      # Takes something that behaves like ARGV with optparse included as an argument.
      #
      # It will take 2 positional arguments once parsed, the first one for the repository location,
      # the optional second one is an IO like object to write to
      class GIT
        COMMAND_NAME = "git".freeze

        attr_reader :source, :target, :labels

        def initialize(args)
          @options = options(args)
          args = @options.parse!
          @source = args.shift
          @target = args.shift || STDOUT
          @labels ||= {}
        end

        def run
          validate!

          ::GitLab::Monitor::GitProber.new(labels: labels, source: source)
                                      .probe_pull
                                      .probe_push
                                      .write_to(@target)
        end

        def options(args)
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options] repository_path [target_file]"
            opts.on("-l", "--labels=key=value,key2=value2", "Labels to append to the metrics") do |val|
              @labels = val.split(",").map { |value| value.split("=").tap { |aa| aa[0] = aa[0].to_sym } }.to_h
            end
            opts
          end
        end

        def help
          @options.help
        end

        def validate!
          fail InvalidCLICommand.new(help) if @source.nil?
          fail InvalidCLICommand.new("Can't find repository #{@source}\n\n#{help}") unless File.directory? @source
        end
      end

      # Database dead tuples runner.
      #
      # It will take a database connection string and print results to STDOUT
      class DatabaseDeadTuples
        COMMAND_NAME = "db-dead-tuples".freeze

        def initialize(args)
          @options = options(args)
          @options.parse!

          @target = args.shift || STDOUT
          @target = File.open(@target, "a") if @target.is_a?(String)
        end

        def options(args)
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options]"
            opts.on("--db-conn=\"dbname=test port=5432\"", "Database connection string") do |val|
              @db_connection_string = val
            end
          end
        end

        def help
          @options.help
        end

        def run
          validate!

          ::GitLab::Monitor::Database::DeadTuplesProber.new(connection_string: @db_connection_string)
                                                       .probe_db
                                                       .write_to(@target)
        end

        private

        def validate!
          fail InvalidCLICommand.new(help) unless @db_connection_string
        end
      end

      # Database blocked queries runner.
      #
      # It will take a database connection string and print results to STDOUT
      class DatabaseBlockedQueries
        COMMAND_NAME = "db-blocked-queries".freeze

        def initialize(args)
          @options = options(args)
          @options.parse!

          @target = args.shift || STDOUT
          @target = File.open(@target, "a") if @target.is_a?(String)
        end

        def options(args)
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options]"
            opts.on("--db-conn=\"dbname=test port=5432\"", "Database connection string") do |val|
              @db_connection_string = val
            end
          end
        end

        def help
          @options.help
        end

        def run
          validate!

          ::GitLab::Monitor::Database::BlockedQueriesProber.new(connection_string: @db_connection_string)
                                                           .probe_db
                                                           .write_to(@target)
        end

        private

        def validate!
          fail InvalidCLICommand.new(help) unless @db_connection_string
        end
      end

      # Database slow queries runner.
      #
      # It will take a database connection string and print results to STDOUT
      class DatabaseSlowQueries
        COMMAND_NAME = "db-slow-queries".freeze

        def initialize(args)
          @options = options(args)
          @options.parse!

          @target = args.shift || STDOUT
          @target = File.open(@target, "a") if @target.is_a?(String)
        end

        def options(args)
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options]"
            opts.on("--db-conn=\"dbname=test port=5432\"", "Database connection string") do |val|
              @db_connection_string = val
            end
          end
        end

        def help
          @options.help
        end

        def run
          validate!

          ::GitLab::Monitor::Database::SlowQueriesProber.new(connection_string: @db_connection_string)
                                                        .probe_db
                                                        .write_to(@target)
        end

        private

        def validate!
          fail InvalidCLICommand.new(help) unless @db_connection_string
        end
      end

      # Database vacuum queries runner.
      #
      # It will take a database connection string and print results to STDOUT
      class DatabaseVacuumQueries
        COMMAND_NAME = "db-vacuum-queries".freeze

        def initialize(args)
          @options = options(args)
          @options.parse!

          @target = args.shift || STDOUT
          @target = File.open(@target, "a") if @target.is_a?(String)
        end

        def options(args)
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options]"
            opts.on("--db-conn=\"dbname=test port=5432\"", "Database connection string") do |val|
              @db_connection_string = val
            end
          end
        end

        def help
          @options.help
        end

        def run
          validate!

          ::GitLab::Monitor::Database::VacuumQueriesProber.new(connection_string: @db_connection_string)
                                                          .probe_db
                                                          .write_to(@target)
        end

        private

        def validate!
          fail InvalidCLICommand.new(help) unless @db_connection_string
        end
      end

      # Run a web server that exposes the metrics specified in a config file
      class Server
        COMMAND_NAME = "web".freeze

        def initialize(args)
          @options = options(args)
          @options.parse!
        end

        def options(args)
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options]"
            opts.on("-c config.yml", "Monitoring config") do |val|
              @config_file = val
            end
          end
        end

        def help
          @options.help
        end

        def run
          validate!

          config = Utils.deep_symbolize_hash_keys(YAML.load_file(@config_file))

          WebExporter.setup(config)
          WebExporter.run!
        end

        private

        def validate!
          fail InvalidCLICommand.new(help) unless @config_file
        end
      end

      # Process runner
      #
      # Takes a pid and name for metrics
      class Process
        COMMAND_NAME = "process".freeze

        def initialize(args)
          @options = options(args)
          @options.parse!

          @target = args.shift || STDOUT
          @target = File.open(@target, "a") if @target.is_a?(String)
        end

        def options(args)
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options]"
            opts.on("--pid=123", "Process ID") do |val|
              @pid = val
            end
            opts.on("--pattern=unicron", "Process command pattern") do |val|
              @pattern = val
            end
            opts.on("--name=NAME", "Process name to be used in metrics") do |val|
              @name = val
            end
            opts.on("--quantiles", "Return quantiles instead of exact metrics") do
              @quantiles = true
            end
          end
        end

        def help
          @options.help
        end

        def run
          ::GitLab::Monitor::ProcessProber.new(pid_or_pattern: @pid || @pattern, name: @name, quantiles: @quantiles)
                                          .probe_memory
                                          .probe_age
                                          .write_to(@target)
        end
      end

      # Sidekiq runner.
      #
      # It will take a Redis connection URL and print results to STDOUT
      class SidekiqRunner
        COMMAND_NAME = "sidekiq".freeze

        def initialize(args)
          @options = options(args)
          @options.parse!

          @target = args.shift || STDOUT
          @target = File.open(@target, "a") if @target.is_a?(String)
        end

        def options(args)
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options]"
            opts.on("--redis-url=\"redis://localhost:6379\"", "Redis URL") do |val|
              @redis_url = val
            end
          end
        end

        def help
          @options.help
        end

        def run
          validate!

          ::GitLab::Monitor::SidekiqProber.new(redis_url: @redis_url)
                                          .probe_queues
                                          .probe_workers
                                          .probe_retries
                                          .write_to(@target)
        end

        private

        def validate!
          fail InvalidCLICommand.new(help) unless @redis_url
        end
      end

      def self.commands
        [
          GIT,
          DatabaseDeadTuples,
          DatabaseBlockedQueries,
          DatabaseSlowQueries,
          DatabaseVacuumQueries,
          Process,
          SidekiqRunner,
          Server
        ].each_with_object({}) do |command_class, commands|
          commands[command_class::COMMAND_NAME] = command_class
          commands
        end
      end
    end
  end
end
