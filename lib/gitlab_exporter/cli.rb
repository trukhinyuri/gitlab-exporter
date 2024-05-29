require "yaml"
require "deep_merge"
require "English"

# TODO: Remove this once we're on Ruby 3
# https://gitlab.com/gitlab-org/gitlab/-/issues/393651
unless YAML.respond_to?(:safe_load_file)
  module YAML # rubocop:disable Style/Documentation
    # Temporary Ruby 2 back-compat workaround.
    #
    # This method only exists as of stdlib 3.0.0:
    # https://ruby-doc.org/stdlib-3.0.0/libdoc/psych/rdoc/Psych.html
    def self.safe_load_file(path, **options)
      YAML.safe_load(File.read(path), **options)
    end
  end
end

module GitLab
  module Exporter
    # Stores runner classes in a single place
    #
    # The entry point is the module method "for" which takes the name of a runner.
    # In case the runner is invalid it will return a NullRunner which fails with an
    # InvalidCLICommand error, which contains the general application usage instructions.
    module CLI
      EXECUTABLE_NAME = "gitlab-exporter".freeze

      def self.for(name)
        commands.fetch(name, NullRunner)
      end

      class InvalidCLICommand < RuntimeError; end

      # Empty runner that will raise an InvalidCLICommand when executed to provide the usage
      # in the exception message
      class NullRunner
        def initialize(args); end

        def run
          fail InvalidCLICommand.new("Usage: #{EXECUTABLE_NAME} <command> [options] [arguments...]\n\n"\
                                     "Available commands are: #{GitLab::Exporter::CLI.commands.keys.join(', ')}")
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

          ::GitLab::Exporter::GitProber.new(labels: labels, source: source)
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

      # Database tuple stats runner.
      #
      # It will take a database connection string and print results to STDOUT
      class DatabaseTupleStats
        COMMAND_NAME = "db-tuple-stats".freeze

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

          ::GitLab::Exporter::Database::TuplesProber.new(connection_string: @db_connection_string)
                                                    .probe_db
                                                    .write_to(@target)
        end

        private

        def validate!
          fail InvalidCLICommand.new(help) unless @db_connection_string
        end
      end

      # Database row counts query runner.
      #
      # This will take the database connection and print the result to STDOUT
      class DatabaseRowCounts
        COMMAND_NAME = "row-counts".freeze

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

          ::GitLab::Exporter::Database::RowCountProber.new(connection_string: @db_connection_string)
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
            opts.on("--extra-config-command command", "Shell command that returns YAML config to be merged
                    with the config file") do |val|
              @extra_config_command = val
            end
          end
        end

        def help
          @options.help
        end

        def merged_config
          config_from_file = Utils.deep_symbolize_hash_keys(YAML.safe_load_file(@config_file, aliases: true))
          config_from_command = extra_config_from_command

          config_from_file.deep_merge!(config_from_command)
        end

        def run
          validate!

          WebExporter.setup(merged_config)
          WebExporter.run!
        end

        private

        def validate!
          fail InvalidCLICommand.new(help) unless @config_file
        end

        def run_extra_config_command
          puts "Using extra config by running command `#{@extra_config_command}`"

          output = `#{@extra_config_command}`
          return output if $CHILD_STATUS == 0

          puts "ERROR: command `#{@extra_config_command}` returned a non-zero code."
          exit(2)
        end

        def extra_config_from_command
          return {} unless @extra_config_command

          Utils.deep_symbolize_hash_keys(YAML.safe_load(run_extra_config_command))
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
            opts.on("--pattern=worker", "Process command pattern") do |val|
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
          ::GitLab::Exporter::ProcessProber.new(pid_or_pattern: @pid || @pattern, name: @name, quantiles: @quantiles)
                                           .probe_stat
                                           .probe_count
                                           .probe_smaps
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

        def options(args) # rubocop:disable Metrics/MethodLength
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options]"
            opts.on("--redis-url=\"redis://localhost:6379\"", "Redis URL") do |val|
              @redis_url = val
            end
            opts.on("--redis-sentinel-username=\"my-sentinel-username\"", "Redis Sentinel username") do |val|
              @redis_sentinel_username = val
            end
            opts.on("--redis-sentinel-password=\"my-sentinel-password\"", "Redis Sentinel password") do |val|
              @redis_sentinel_password = val
            end
            opts.on("--redis-sentinels=HOST1:PORT1,HOST2:PORT2", Array, "List of Redis Sentinels") do |val|
              @redis_sentinels = val.map { |item|
                host, port = item.split(":")
                { host: host, port: port.to_i }
              }
            end
          end
        end

        def help
          @options.help
        end

        def run
          validate!

          prober = ::GitLab::Exporter::SidekiqProber.new(redis_url: @redis_url,
                                                         redis_sentinels: @redis_sentinels,
                                                         redis_sentinel_username: @redis_sentinel_username,
                                                         redis_sentinel_password: @redis_sentinel_password,
                                                         logger: Logger.new(STDERR))

          prober
            .probe_stats
            .probe_queues
            .probe_jobs_limit
            .probe_workers
            .probe_retries
            .write_to(@target)
        end

        private

        def validate!
          fail InvalidCLICommand.new(help) unless @redis_url
        end
      end

      # Process runner
      #
      # Takes a pid and name for metrics
      class GitProcess
        COMMAND_NAME = "git-process".freeze

        def initialize(args)
          @options = options(args)
          @options.parse!

          @target = args.shift || STDOUT
          @target = File.open(@target, "a") if @target.is_a?(String)
        end

        def options(args)
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options]"
            opts.on("--quantiles", "Return quantiles instead of exact metrics") do
              @quantiles = true
            end
          end
        end

        def help
          @options.help
        end

        def run
          ::GitLab::Exporter::GitProcessProber.new(quantiles: @quantiles)
                                              .probe_git
                                              .write_to(@target)
        end
      end

      def self.commands
        [
          GIT,
          DatabaseTupleStats,
          DatabaseRowCounts,
          Process,
          GitProcess,
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
