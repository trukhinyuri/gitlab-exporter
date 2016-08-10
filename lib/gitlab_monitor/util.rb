module GitLab
  module Monitor
    # Simple time wrapper that provides a to_i and wraps the execution result
    TrackedResult = Struct.new(:result, :time) do
      def to_i
        time
      end
    end

    # Time tracking object
    #
    # Provides a simple time tracking, and returns back the result plus the tracked time
    # wraped in a TrackedResult struct
    class TimeTracker
      def track
        @start = Time.now.to_f
        result = yield
        TrackedResult.new(result, Time.now.to_f - @start)
      end
    end
  end
end
