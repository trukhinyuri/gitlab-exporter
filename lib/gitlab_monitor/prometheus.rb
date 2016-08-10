module GitLab
  module Monitor
    # Prometheus metrics container
    #
    # Provides a simple API to `add` metrics and then turn them `to_s` which will just
    # dump all the metrics in prometheus format
    #
    # The add method also can take any arbitrary amount of labels in a `key: value` format.
    class PrometheusMetrics
      def initialize
        @metrics = {}
      end

      def add(name, value, **labels)
        @metrics[name] = { value: value, labels: labels, timestamp: (Time.now.to_f * 1000).to_i }
        self
      end

      def to_s
        buffer = StringIO.new
        @metrics.each do |name, metrics|
          buffer.write(name.to_s)
          labels = (metrics[:labels] || {}).map { |label, value| "#{label}=\"#{value}\"" }.join(",")
          buffer.write("{#{labels}}") unless labels.empty?
          buffer.write(" #{metrics[:value]} #{metrics[:timestamp]}\n")
        end
        buffer.rewind
        buffer.read
      end
    end
  end
end
