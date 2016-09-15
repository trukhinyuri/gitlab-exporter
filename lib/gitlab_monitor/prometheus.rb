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
        @metrics = Hash.new { |h, k| h[k] = [] }
      end

      def add(name, value, **labels)
        @metrics[name] << { value: value, labels: labels, timestamp: (Time.now.to_f * 1000).to_i }
        self
      end

      def to_s
        buffer = StringIO.new
        @metrics.each do |name, measurements|
          measurements.each do |measurement|
            buffer.write(name.to_s)
            labels = (measurement[:labels] || {}).map { |label, value| "#{label}=\"#{value}\"" }.join(",")
            buffer.write("{#{labels}}") unless labels.empty?
            buffer.write(" #{measurement[:value]} #{measurement[:timestamp]}\n")
          end
        end
        buffer.rewind
        buffer.read
      end
    end
  end
end
