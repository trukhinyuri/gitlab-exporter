require "sinatra/base"

module GitLab
  module Monitor
    # Metrics web exporter
    class WebExporter < Sinatra::Base
      class << self
        def setup(config)
          config[:probes].each do |probe_name, params|
            prober_class_name = params.delete(:class_name) || Utils.camel_case_string("#{probe_name}_prober")
            prober_class = GitLab::Monitor.const_get(prober_class_name)

            get "/#{probe_name}" do
              prober = prober_class.new(params[:opts], metrics: PrometheusMetrics.new(include_timestamp: false))
              params[:methods].each do |meth|
                prober.send(meth)
              end
              prober.write_to(response)
            end
          end
        end
      end
    end
  end
end
