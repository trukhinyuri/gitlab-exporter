require "open3"

module GitLab
  module Monitor
    class Git
      def initialize(repo)
        fail "Repository #{repo} does not exists" unless Dir.exists? repo
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

      def empty_commit(message="Beep")
        @tracker.track { execute("git commit --allow-empty -m '#{message}'") }
      end

      private

      def execute(command)
        result = CommandResult.new(*Open3.capture2e(command, chdir: @repo))
        fail "Command #{command} failed with status #{result.status}\n#{result.stdout}" if result.failed?
        result
      end
    end

    CommandResult = Struct.new(:stdout, :status) do
      def failed?
        status != 0
      end

      def status
        self[:status].exitstatus
      end

      def to_s
        stdout
      end
    end
  end
end
