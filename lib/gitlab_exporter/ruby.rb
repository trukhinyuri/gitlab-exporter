# frozen_string_literal: true

module GitLab
  module Exporter
    # Probes a current process GC for info then writes metrics to a target
    class RubyProber
      def initialize(options, metrics: PrometheusMetrics.new, logger: nil) # rubocop:disable Lint/UnusedMethodArgument
        @metrics = metrics
        @use_quantiles = options.fetch(:quantiles, false)
      end

      def probe_gc
        GC.stat.each do |stat, value|
          @metrics.add("ruby_gc_stat_#{stat}", value.to_i, @use_quantiles)
        end

        self
      end
    end
  end
end
