require "webrick"
require "English"
require "cgi"
require "stringio"

require_relative "tls_helper"

module GitLab
  module Exporter
    # Metrics web exporter backed directly by WEBrick (no Sinatra/Rack).
    class WebExporter
      DEFAULT_WEB_SERVER = "webrick".freeze
      DEFAULT_LISTEN_ADDRESS = "0.0.0.0".freeze
      DEFAULT_LISTEN_PORT = 9168
      DEFAULT_MEMORY_THRESHOLD = 1024

      # Security response headers previously added by Sinatra's Rack::Protection
      # middleware, which is gone now that we serve directly via WEBrick. Kept for
      # parity so scanners and consumers see the same headers as before.
      SECURITY_HEADERS = {
        "X-Content-Type-Options" => "nosniff",
        "X-Frame-Options" => "SAMEORIGIN",
        "X-XSS-Protection" => "1; mode=block"
      }.freeze

      class << self
        include TLSHelper

        def setup(config)
          server_config = config[:server] || {}

          memory_threshold = server_config.fetch(:memory_threshold, DEFAULT_MEMORY_THRESHOLD)
          @memory_threshold = memory_threshold.to_i * 1024

          @server = build_server(server_config)
          mount_probes(config[:probes])

          # Defrag heap after everything is loaded into memory.
          GC.compact
        end

        def run!
          trap_signals
          @server.start
        end

        private

        def build_server(config)
          warn_deprecated_server(config[:name])

          options = {
            Port: config.fetch(:listen_port, DEFAULT_LISTEN_PORT),
            BindAddress: config.fetch(:listen_address, DEFAULT_LISTEN_ADDRESS)
          }

          if config.fetch(:tls_enabled, "false").to_s == "true"
            validate_tls_config(config)
            options.merge!(webrick_tls_config(config))
          end

          WEBrick::HTTPServer.new(**options)
        end

        # The web server used to be configurable (e.g. Puma) via the `server.name`
        # setting when the exporter ran on top of Sinatra. It now always uses WEBrick,
        # so the setting is ignored. Warn operators whose config still sets it.
        #
        # TODO: This is step one of a two-step deprecation. In a future major release,
        # raise instead of warning so the ignored `server.name` setting fails loudly.
        def warn_deprecated_server(name)
          return if name.nil? || name.to_s == DEFAULT_WEB_SERVER

          warn "DEPRECATION: `server.name` (#{name.inspect}) is no longer supported and is ignored; " \
               "the exporter now always uses WEBrick. Please remove `server.name` from your config."
        end

        def mount_probes(probes)
          (probes || {}).each do |probe_name, params|
            opts =
              if params.delete(:multiple)
                params
              else
                { probe_name => params }
              end

            @server.mount_proc("/#{probe_name}") do |_request, response|
              handle_probe(response, opts)
            end
          end
        end

        def handle_probe(response, opts)
          # A memory killer that kills the process if we exceeded a certain threshold.
          check_memory_threshold!

          prober = Prober.new(metrics: PrometheusMetrics.new(include_timestamp: false), logger: @server.logger, **opts)
          prober.probe_all

          buffer = StringIO.new
          prober.write_to(buffer)

          SECURITY_HEADERS.each do |header, value|
            response[header] = value
          end
          response.content_type = "text/plain; version=0.0.4; charset=utf-8"
          response.body = buffer.string
        ensure
          # Performs a major GC after each request. We found that this helps to free up
          # several MB of memory in conjunction with stricter malloc config.
          # See https://gitlab.com/gitlab-org/gitlab/-/issues/297241
          GC.start
        end

        def check_memory_threshold!
          usage = memory_usage
          return if usage <= @memory_threshold

          puts "Memory usage of #{usage} exceeded threshold of #{@memory_threshold}, signalling KILL"
          Process.kill("KILL", $PID)
        end

        def memory_usage
          # Use the block form so the pipe is closed automatically even if the
          # read raises, avoiding a file-descriptor leak.
          mem = IO.popen(%W[ps -o rss= -p #{$PID}], &:read)

          return 0 unless $CHILD_STATUS.to_i.zero?

          mem.to_i
        end

        def trap_signals
          %w[INT TERM].each do |signal|
            trap(signal) { @server.shutdown }
          end
        end
      end
    end
  end
end
