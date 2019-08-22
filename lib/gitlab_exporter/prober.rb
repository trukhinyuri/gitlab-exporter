module GitLab
  module Exporter
    # A class to combine multiple probers into one
    class Prober
      def initialize(prober_opts, metrics: PrometheusMetrics.new)
        @prober_opts = prober_opts
        @metrics     = metrics

        resolve_prober_classes
      end

      def probe_all
        @prober_opts.each do |_probe_name, params|
          Utils.wrap_in_array(params[:opts]).each do |opts|
            prober = params[:class].new(opts, metrics: @metrics)
            params[:methods].each do |meth|
              prober.send(meth)
            end
          end
        end
      end

      def write_to(target)
        target.write(@metrics.to_s)
      end

      private

      def resolve_prober_classes
        @prober_opts.each do |probe_name, params|
          prober_class_name = params[:class_name] || Utils.camel_case_string("#{probe_name}_prober")

          klass = prober_class_name.split("::").reduce(GitLab::Exporter) { |a, e| a.const_get(e) }

          params[:class] = klass
        end
      end
    end
  end
end
