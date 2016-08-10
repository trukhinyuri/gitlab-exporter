module GitLab
  module Monitor
    module CLI
      EXECUTABLE_NAME = "gitlab-mon"

      def self.for(name)
        commands.fetch(name, NullRunner)
      end

      class InvalidCLICommand < RuntimeError; end

      class NullRunner
        def initialize(args)
        end

        def run
          fail InvalidCLICommand.new "Usage: #{EXECUTABLE_NAME} <command> [options] [arguments...]\n\n"\
                                      "Available commands are: #{commands.keys.join(', ')}"
        end
      end

      class GIT
        COMMAND_NAME="git"

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

          ::GitLab::Monitor::GitProber.new(self).
            probe_pull.
            probe_push.
            write_to(@target)
        end

        def options(args)
          args.options do |opts|
            opts.banner = "Usage: #{EXECUTABLE_NAME} #{COMMAND_NAME} [options] repository_path [target_file]"
            opts.on("-l", "--labels=key=value,key2=value2", "Labels to append to the metrics") { |val|
              @labels = val.split(",").map{|value| value.split("=").tap{|aa| aa[0] = aa[0].to_sym} }.to_h
            }
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

      def self.commands
        [GIT].inject({}) do |commands, command_class|
          commands[command_class::COMMAND_NAME] = command_class
          commands
        end
      end
    end
  end
end
