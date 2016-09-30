module GitLab
  module Monitor
    # Prometheus metrics container
    #
    # Provides a simple API to `add` metrics and then turn them `to_s` which will just
    # dump all the metrics in prometheus format
    #
    # The add method also can take any arbitrary amount of labels in a `key: value` format.
    class PrometheusMetrics
      def initialize(include_timestamp: true)
        @metrics = Hash.new { |h, k| h[k] = [] }
        @include_timestamp = include_timestamp
      end

      def add(name, value, **labels)
        @metrics[name] << { value: value, labels: labels, timestamp: (Time.now.to_f * 1000).to_i }
        self
      end

      def to_s
        buffer = ""
        @metrics.each do |name, measurements|
          measurements.each do |measurement|
            buffer << name.to_s
            labels = (measurement[:labels] || {}).map { |label, value| "#{label}=\"#{value}\"" }.join(",")
            buffer << "{#{labels}}" unless labels.empty?
            buffer << " #{measurement[:value]}"
            buffer << " #{measurement[:timestamp]}" if @include_timestamp
            buffer << "\n"
          end
        end
        buffer
      end
    end
  end
end
