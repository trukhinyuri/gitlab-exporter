require "spec_helper"
require "gitlab_exporter/cli"

module GitLab
  module Exporter
    module CLI
      describe SidekiqRunner, :integration do
        let(:redis_url) { ENV.fetch("REDIS_URL", "redis://localhost:6379") }
        let(:redis_sentinel_url) { ENV.fetch("REDIS_SENTINEL_URL", "redis://mymaster:6379") }
        let(:redis_sentinel_password) { ENV.fetch("REDIS_SENTINEL_PASSWORD", "my-sentinel-password") }
        let(:redis_sentinels) do
          sentinels = ENV.fetch("REDIS_SENTINELS", "localhost:26379")
          sentinels.split(" ")
        end
        let(:io) { StringIO.new }

        it "can properly reach out to redis" do
          args = CLIArgs.new([io], options: { /^--redis-url/ => redis_url })
          runner = SidekiqRunner.new(args)

          expect { runner.run }.not_to raise_error
        end

        it "can properly reach out to redis-sentinel" do
          args = CLIArgs.new([io], options: { /^--redis-url/ => redis_sentinel_url,
                                              /^--redis-sentinel-password/ => redis_sentinel_password,
                                              /^--redis-sentinels/ => redis_sentinels })
          runner = SidekiqRunner.new(args)

          expect { runner.run }.not_to raise_error
        end
      end
    end
  end
end
