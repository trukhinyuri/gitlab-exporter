module GitLab
  module Monitor
    TrackedResult = Struct.new(:result, :time) do
      def to_i
        time
      end
    end

    class TimeTracker
      def track
        @start = Time.now.to_f
        result = yield
        TrackedResult.new(result, Time.now.to_f - @start)
      end
    end
  end
end
