require "spec_helper"
require "gitlab_exporter/web_exporter"
require "net/http"
require "timeout"

describe GitLab::Exporter::WebExporter do
  # Each test builds a fresh server via `.setup`; drop the reference afterwards
  # so class-level state does not leak between examples.
  after do
    described_class.instance_variable_set(:@server, nil)
  end

  describe ".setup" do
    let(:probes) { {} }

    it "builds a WEBrick server with the configured port and bind address" do
      options = capture_server_options(server: { listen_address: "127.0.0.1", listen_port: 12_345 })

      expect(options).to include(Port: 12_345, BindAddress: "127.0.0.1")
    end

    it "falls back to the default port and bind address" do
      options = capture_server_options({})

      expect(options).to include(Port: 9168, BindAddress: "0.0.0.0")
    end

    it "mounts a handler for each configured probe" do
      server = instance_double(WEBrick::HTTPServer)
      allow(WEBrick::HTTPServer).to receive(:new).and_return(server)

      expect(server).to receive(:mount_proc).with("/ruby")

      described_class.setup(server: {}, probes: { ruby: { methods: %w[probe_gc], opts: {} } })
    end

    it "raises when TLS is enabled but no certificate is configured" do
      expect {
        described_class.setup(server: { tls_enabled: true }, probes: probes)
      }.to raise_error(/tls_cert_path not specified/)
    end

    # Capture the keyword options passed to WEBrick without binding a real socket.
    def capture_server_options(config)
      captured = nil
      allow(WEBrick::HTTPServer).to receive(:new) do |**options|
        captured = options
        instance_double(WEBrick::HTTPServer)
      end

      described_class.setup(config.merge(probes: {}))
      captured
    end
  end

  describe "deprecating the server.name setting" do
    it "warns when a non-WEBrick server is requested" do
      expect {
        described_class.send(:warn_deprecated_server, "puma")
      }.to output(/DEPRECATION.*no longer supported/).to_stderr
    end

    it "does not warn when the server is webrick" do
      expect { described_class.send(:warn_deprecated_server, "webrick") }.not_to output.to_stderr
    end

    it "does not warn when no server name is set" do
      expect { described_class.send(:warn_deprecated_server, nil) }.not_to output.to_stderr
    end
  end

  describe "serving probe requests" do
    let(:config) do
      {
        server: { listen_address: "127.0.0.1", listen_port: 0 },
        probes: { ruby: { methods: %w[probe_gc], opts: {} } }
      }
    end

    let(:server) { described_class.instance_variable_get(:@server) }
    let(:base_uri) { "http://127.0.0.1:#{server.listeners.first.addr[1]}" }

    before do
      # WEBrick binds its logger and access log to $stderr at construction time
      # and emits a startup banner; silence $stderr around setup so the log
      # device is a throwaway buffer and the test output stays clean.
      original_stderr = $stderr
      $stderr = StringIO.new
      begin
        described_class.setup(config)
      ensure
        $stderr = original_stderr
      end

      @server_thread = Thread.new { server.start }
      Timeout.timeout(5) { sleep 0.01 until server.status == :Running }
    end

    after do
      server.shutdown
      @server_thread&.join(5)
    end

    it "returns Prometheus metrics for a known probe" do
      response = Net::HTTP.get_response(URI("#{base_uri}/ruby"))

      expect(response.code).to eq("200")
      expect(response.content_type).to eq("text/plain")
      expect(response["Content-Type"]).to include("version=0.0.4")
      expect(response.body).to match(/ruby_gc_stat_count \d+/)
    end

    it "sets the security headers previously provided by Rack::Protection" do
      response = Net::HTTP.get_response(URI("#{base_uri}/ruby"))

      expect(response["X-Content-Type-Options"]).to eq("nosniff")
      expect(response["X-Frame-Options"]).to eq("SAMEORIGIN")
      expect(response["X-XSS-Protection"]).to eq("1; mode=block")
    end

    it "returns 404 for unknown paths" do
      response = Net::HTTP.get_response(URI("#{base_uri}/does-not-exist"))

      expect(response.code).to eq("404")
    end
  end
end
