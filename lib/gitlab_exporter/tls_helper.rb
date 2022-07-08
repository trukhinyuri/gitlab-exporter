# Contains helper methods to generate TLS related configuration for web servers
module TLSHelper
  CERT_REGEX = /-----BEGIN CERTIFICATE-----(?:.|\n)+?-----END CERTIFICATE-----/.freeze

  def validate_tls_config(config)
    %i[tls_cert_path tls_key_path].each do |key|
      fail "TLS enabled, but #{key} not specified in config" unless config.key?(key)

      fail "File specified via #{key} not found: #{config[key]}" unless File.exist?(config[key])
    end
  end

  def webrick_tls_config(config)
    # This monkey-patches WEBrick::GenericServer, so never require this unless TLS is enabled.
    require "webrick/ssl"

    certs = load_ca_certs_bundle(File.binread(config[:tls_cert_path]))

    {
      SSLEnable: true,
      SSLCertificate: certs.shift,
      SSLPrivateKey: OpenSSL::PKey.read(File.binread(config[:tls_key_path])),
      # SSLStartImmediately is true by default according to the docs, but when WEBrick creates the
      # SSLServer internally, the switch was always nil for some reason. Setting this explicitly fixes this.
      SSLStartImmediately: true,
      SSLExtraChainCert: certs
    }
  end

  # In Ruby OpenSSL v3.0.0, this can be replaced by OpenSSL::X509::Certificate.load
  # https://github.com/ruby/openssl/issues/254
  def load_ca_certs_bundle(ca_certs_string)
    return [] unless ca_certs_string

    ca_certs_string.scan(CERT_REGEX).map do |ca_cert_string|
      OpenSSL::X509::Certificate.new(ca_cert_string)
    end
  end
end
