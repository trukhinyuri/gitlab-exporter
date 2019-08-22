require "open3"

module GitLab
  module Exporter
    # Git monitoring helping class
    #
    # Takes a repository path for construction and provides 2 main methods:
    #   - pull
    #   - push
    #
    # Both methods return a CommandResult which includes the output of the execution
    # plus the tracked execution time.
    class Git
      def initialize(repo)
        fail "Repository #{repo} does not exists" unless Dir.exist? repo
        @repo = repo
        @tracker = TimeTracker.new
      end

      def pull
        @tracker.track { execute "git pull -q" }
      end

      def push
        empty_commit
        @tracker.track { execute "git push -q" }
      end

      def empty_commit(message = "Beep")
        @tracker.track { execute("git commit --allow-empty -m '#{message}'") }
      end

      private

      def execute(command)
        result = CommandResult.new(*Open3.capture2e(command, chdir: @repo))
        fail "Command #{command} failed with status #{result.status}\n#{result.stdout}" if result.failed?
        result
      end
    end

    # Result of a command
    #
    # Provides some handy methods for checking if the execution failed and a simple to_s that will
    # return the command output
    CommandResult = Struct.new(:stdout, :status) do
      def failed?
        status.nonzero?
      end

      def status
        self[:status].exitstatus
      end

      def to_s
        stdout
      end
    end

    # Handles creating a Git object, probing for both pull and push, and finally writing to metrics
    #
    # Optionally takes a metrics object which by default is a PrometheusMetrics, useful to change the
    # metrics writer to something else.
    class GitProber
      def initialize(opts, metrics: PrometheusMetrics.new)
        @metrics = metrics
        @labels = opts[:labels] || {}
        @git = Git.new(opts[:source])
      end

      def probe_pull
        @metrics.add "git_pull_time_milliseconds", (@git.pull.time * 1000).to_i, **@labels
        self
      end

      def probe_push
        @metrics.add "git_push_time_milliseconds", (@git.push.time * 1000).to_i, **@labels
        self
      end

      def write_to(target)
        target.write(@metrics.to_s)
      end
    end

    # A special prober for git processes
    class GitProcessProber
      def initialize(opts, metrics: PrometheusMetrics.new)
        @opts    = opts
        @metrics = metrics
      end

      def probe_git # rubocop:disable Metrics/MethodLength
        counts = Hash.new(0)

        Utils.pgrep("^git ").each do |pid|
          process_cmd = begin
                          File.read("/proc/#{pid}/cmdline")
                        rescue
                          "" # Process file is gone (race condition)
                        end
          subcommand  = self.class.extract_subcommand(process_cmd)
          next unless subcommand # Unlikely, but just to be safe

          name = "git #{subcommand}"
          counts[name] += 1

          prober = ProcessProber.new(
            {
              name: name,
              pid_or_pattern: pid,
              quantiles: @opts[:quantiles]
            },
            metrics: @metrics
          )

          prober
            .probe_stat
        end

        counts.each do |name, count|
          @metrics.add("process_count", count, name: name)
        end

        self
      end

      def write_to(target)
        target.write(@metrics.to_s)
      end

      def self.extract_subcommand(cmd)
        return if cmd.empty?
        cmd_splitted = cmd.split("\u0000") # cmdline does not return it space-separated

        cmd_splitted.shift # Because it's "git"
        cmd_splitted.shift while cmd_splitted.first &&
                                 (cmd_splitted.first.empty? || cmd_splitted.first !~ /^[^-][a-z\-]*$/)

        cmd_splitted[0]
      end
    end
  end
end
