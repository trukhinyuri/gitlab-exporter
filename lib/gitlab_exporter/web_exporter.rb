require "sinatra/base"
require "English"

module GitLab
  module Exporter
    # Metrics web exporter
    class WebExporter < Sinatra::Base
      # A middleware to kill the process if we exceeded a certain threshold
      class MemoryKillerMiddleware
        def initialize(app, memory_threshold)
          @app = app
          @memory_threshold = memory_threshold.to_i * 1024
        end

        def call(env)
          if memory_usage > @memory_threshold
            puts "Memory usage of #{memory_usage} exceeded threshold of #{@memory_threshold}, signalling KILL"
            Process.kill("KILL", $PID)
          end

          @app.call(env)
        end

        private

        def memory_usage
          io = IO.popen(%W(ps -o rss= -p #{$PID}))

          mem = io.read
          io.close

          return 0 unless $CHILD_STATUS.to_i.zero?

          mem.to_i
        end
      end

      class << self
        def setup(config)
          setup_server(config[:server])
          setup_probes(config[:probes])

          memory_threshold = (config[:server] && config[:server][:memory_threshold]) || 1024
          use MemoryKillerMiddleware, memory_threshold
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
              content_type "text/plain; version=0.0.4"
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
