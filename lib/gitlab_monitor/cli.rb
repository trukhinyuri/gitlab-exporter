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

          ::GitLab::Monitor::GitProber.new(self)
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

      class DatabaseDeadTuples
        COMMAND_NAME = "db-dead-tuples".freeze

        def initialize(args)
          @options = options(args)
          @options.parse!
        end

        def options(args)
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options]"
            opts.on(
              "-i", "--interval [NUMBER]", Numeric, "Interval (in seconds) at which data is collected. Default is 60."
            ) do |val|
              @interval = val || 60
            end
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
          run_loop
        end

        private

        def validate!
          fail InvalidCLICommand.new(help) unless @db_connection_string
        end

        def run_loop
          collector = ::GitLab::Monitor::DatabaseDeadTuplesCollector.new(connection_string: @db_connection_string)
          metrics   = PrometheusMetrics.new

          loop do
            result = collector.run

            result.each do |table_name, dead_tuples_count|
              metrics.add("pg_dead_tuples", dead_tuples_count, table_name: table_name)
            end

            puts metrics.to_s

            sleep @interval
          end
        end
      end

      def self.commands
        [GIT, DatabaseDeadTuples].each_with_object({}) do |command_class, commands|
          commands[command_class::COMMAND_NAME] = command_class
          commands
        end
      end
    end
  end
end
