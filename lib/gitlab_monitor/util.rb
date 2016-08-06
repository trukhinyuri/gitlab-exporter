module GitLab
  module Monitor
    class TimeTracker
      def track
        @start = Time.now.to_f
        yield
        Time.now.to_f - @start
      end
    end
  end
end

