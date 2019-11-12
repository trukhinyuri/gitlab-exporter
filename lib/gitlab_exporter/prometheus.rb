require "quantile"

module GitLab
  module Exporter
    # Prometheus metrics container
    #
    # Provides a simple API to `add` metrics and then turn them `to_s` which will just
    # dump all the metrics in prometheus format
    #
    # The add method also can take any arbitrary amount of labels in a `key: value` format.
    class PrometheusMetrics
      def initialize(include_timestamp: true)
        @metrics = Hash.new { |h, k| h[k] = [] }
        @quantiles = Hash.new { |h, k| h[k] = [] }
        @include_timestamp = include_timestamp
      end

      def add(name, value, quantile = false, **labels)
        fail "value '#{value}' must be a number" unless value.is_a?(Numeric)

        if quantile
          @quantiles[{ name: name, labels: labels }] << value
        else
          @metrics[name] << { value: value, labels: labels, timestamp: (Time.now.to_f * 1000).to_i }
        end

        self
      end

      def to_s
        add_quantiles_to_metrics

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

      private

      def add_quantiles_to_metrics
        @quantiles.each do |data, measurements|
          estimator = Quantile::Estimator.new

          measurements.each do |value|
            estimator.observe(value)
          end

          estimator.invariants.each do |invariant|
            data[:labels][:quantile] = "#{(invariant.quantile * 100).to_i}th"

            add(data[:name], estimator.query(invariant.quantile), **data[:labels])
          end
        end
      end
    end
  end
end
