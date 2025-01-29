require "sinatra/base"
require "English"
require "cgi"

require_relative "rack_vulndb_255039_patch"
require_relative "tls_helper"

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
          io = IO.popen(%W[ps -o rss= -p #{$PID}])

          mem = io.read
          io.close

          return 0 unless $CHILD_STATUS.to_i.zero?

          mem.to_i
        end
      end

      # Performs a major GC after each request. We found that this helps to free up
      # several MB of memory in conjunction with sricter malloc config.
      # See https://gitlab.com/gitlab-org/gitlab/-/issues/297241
      class RunGC
        def initialize(app)
          @app = app
        end

        def call(env)
          @app.call(env).tap do
            GC.start
          end
        end
      end

      class << self
        include TLSHelper

        DEFAULT_WEB_SERVER = "webrick".freeze

        def setup(config)
          setup_server(config[:server])
          setup_probes(config[:probes])

          memory_threshold = (config[:server] && config[:server][:memory_threshold]) || 1024
          use MemoryKillerMiddleware, memory_threshold
          use Rack::Logger
          use RunGC

          # Defrag heap after everything is loaded into memory.
          GC.compact
        end

        def logger
          request.logger
        end

        def setup_server(config)
          config ||= {}

          set(:server, config.fetch(:name, DEFAULT_WEB_SERVER))
          set(:port, config.fetch(:listen_port, 9168))

          # Depending on whether TLS is enabled or not, bind string
          # will be different.
          if config.fetch(:tls_enabled, "false").to_s == "true"
            set_tls_config(config)
          else
            set(:bind, config.fetch(:listen_address, "0.0.0.0"))
          end
        end

        def set_tls_config(config) # rubocop:disable Naming/AccessorMethodName
          validate_tls_config(config)

          web_server = config.fetch(:name, DEFAULT_WEB_SERVER)
          if web_server == "webrick"
            set_webrick_tls(config)
          elsif web_server == "puma"
            set_puma_tls(config)
          else
            fail "TLS not supported for web server `#{web_server}`."
          end
        end

        def set_webrick_tls(config) # rubocop:disable Naming/AccessorMethodName
          server_settings = {}
          server_settings.merge!(webrick_tls_config(config))

          set(:bind, config.fetch(:listen_address, "0.0.0.0"))
          set(:server_settings, server_settings)
        end

        def set_puma_tls(config) # rubocop:disable Naming/AccessorMethodName
          listen_address = config.fetch(:listen_address, "0.0.0.0")
          listen_port = config.fetch(:listen_port, 8443)
          tls_cert_path = CGI.escape(config.fetch(:tls_cert_path))
          tls_key_path = CGI.escape(config.fetch(:tls_key_path))

          bind_string = "ssl://#{listen_address}:#{listen_port}?cert=#{tls_cert_path}&key=#{tls_key_path}"

          set(:bind, bind_string)
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
              content_type "text/plain; version=0.0.4; charset=utf-8"
              prober = Prober.new(metrics: PrometheusMetrics.new(include_timestamp: false), logger: logger, **opts)

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
