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
          set(:port, config.fetch(:listen_port, 9168))
        end

        def setup_probes(config)
          (config || {}).each do |probe_name, params|
            opts =
              if params.delete(:multiple)
                params
              else
                { probe_name => params }
              end

            get "/#{probe_name}" do
              prober = Prober.new(opts, metrics: PrometheusMetrics.new(include_timestamp: false))

              prober.probe_all
              prober.write_to(response)

              response
            end
          end
        end
      end
    end
  end
end
