require "spec_helper"
require "gitlab_exporter/sidekiq"
require "tempfile"
require "openssl"

describe GitLab::Exporter::SidekiqProber do
  let(:metrics) { GitLab::Exporter::PrometheusMetrics.new }

  def create_test_certificate_and_key
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("CN=localhost")
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after = Time.now + 365 * 24 * 60 * 60
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    [cert, key]
  end

  describe "#redis_options" do
    it "includes ssl_params from file paths" do
      cert, key = create_test_certificate_and_key

      cert_file = Tempfile.new("cert.crt")
      key_file = Tempfile.new("key.key")

      cert_file.write(cert.to_pem)
      cert_file.rewind
      key_file.write(key.to_pem)
      key_file.rewind

      prober = described_class.new(
        metrics: metrics,
        redis_url: "rediss://localhost:6380",
        redis_ssl_params: { cert: cert_file.path, key: key_file.path }
      )

      options = prober.send(:redis_options)

      expect(options[:url]).to eq("rediss://localhost:6380")
      expect(options[:ssl_params]).to be_a(Hash)
      expect(options[:ssl_params][:cert]).to be_a(OpenSSL::X509::Certificate)
      expect(options[:ssl_params][:key]).to be_a(OpenSSL::PKey::RSA)

      cert_file.close
      key_file.close
    end

    it "includes ssl_params when already parsed" do
      cert, key = create_test_certificate_and_key

      prober = described_class.new(
        metrics: metrics,
        redis_url: "rediss://localhost:6380",
        redis_ssl_params: { cert: cert, key: key }
      )

      options = prober.send(:redis_options)

      expect(options[:url]).to eq("rediss://localhost:6380")
      expect(options[:ssl_params][:cert]).to equal(cert)
      expect(options[:ssl_params][:key]).to equal(key)
    end

    it "excludes ssl_params when not provided" do
      prober = described_class.new(
        metrics: metrics,
        redis_url: "redis://localhost:6379"
      )

      options = prober.send(:redis_options)

      expect(options[:url]).to eq("redis://localhost:6379")
      expect(options).not_to have_key(:ssl_params)
    end

    it "includes credentials when provided" do
      prober = described_class.new(
        metrics: metrics,
        redis_url: "redis://localhost:6379",
        redis_username: "user",
        redis_password: "pass"
      )

      options = prober.send(:redis_options)

      expect(options[:username]).to eq("user")
      expect(options[:password]).to eq("pass")
    end
  end
end
