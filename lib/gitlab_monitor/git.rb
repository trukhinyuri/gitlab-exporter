require "open3"

module GitLab
  module Monitor
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
      def initialize(options, metrics: PrometheusMetrics.new)
        @metrics = metrics
        @labels = options.labels || {}
        @git = Git.new(options.source)
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
  end
end
