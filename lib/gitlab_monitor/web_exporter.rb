require "sinatra/base"

module GitLab
  module Monitor
    # Metrics web exporter
    class WebExporter < Sinatra::Base
      class << self
        def setup(config)
          setup_server(config[:server])
          setup_probes(config[:probes])
        end

        def setup_server(config)
          config ||= {}

          set(:bind, config.fetch(:listen_address, "0.0.0.0"))
          set(:port, config.fetch(:listen_port, 4567))
        end

        def setup_probes(config) # rubocop:disable Metrics/AbcSize
          (config || {}).each do |probe_name, params|
            prober_class_name = params.delete(:class_name) || Utils.camel_case_string("#{probe_name}_prober")
            prober_class = resolve_prober_class(prober_class_name)

            get "/#{probe_name}" do
              Utils.wrap_in_array(params[:opts]).each do |opts|
                prober = prober_class.new(opts, metrics: PrometheusMetrics.new(include_timestamp: false))
                params[:methods].each do |meth|
                  prober.send(meth)
                end
                prober.write_to(response)
              end

              response
            end
          end
        end

        def resolve_prober_class(prober_class_name)
          prober_class_name.split("::").reduce(GitLab::Monitor) do |ancestor, const_name|
            ancestor.const_get(const_name)
          end
        end
      end
    end
  end
end
