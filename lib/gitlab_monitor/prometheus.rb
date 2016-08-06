module GitLab
  module Monitor
    class PrometheusMetrics
      def initialize
        @metrics = {}
      end

      def add(name, value, **labels)
        @metrics[name] = { value: value, labels: labels, timestamp: (Time.now.to_f * 1000).to_i}
        self
      end

      def to_s
        buffer = StringIO.new
        @metrics.each { |name, metrics|
          buffer.write("#{name}")
          labels = (metrics[:labels] || {}).map { |label, value| "#{label}=\"#{value}\"" }.join(",")
          buffer.write("{#{labels}}") unless labels.empty?
          buffer.write(" #{metrics[:value]} #{metrics[:timestamp]}\n")
        }
        buffer.rewind
        buffer.read
      end
    end
  end
end
