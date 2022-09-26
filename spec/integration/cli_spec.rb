require "spec_helper"
require "gitlab_exporter/cli"

module GitLab
  module Exporter
    module CLI
      describe SidekiqRunner, :integration do
        let(:redis_url) { ENV.fetch("REDIS_URL", "redis://localhost:6379") }
        let(:io) { StringIO.new }

        it "can properly reach out to redis" do
          args = CLIArgs.new([io], options: { /^--redis-url/ => redis_url })
          runner = SidekiqRunner.new(args)

          expect { runner.run }.not_to raise_error
        end
      end
    end
  end
end
