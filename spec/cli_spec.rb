require "spec_helper"
require "gitlab_exporter/cli"
require "optparse"

context "With valid pair of repositories" do
  let(:repos) { GitRepoBuilder.new }

  after do
    repos.cleanup
  end

  describe GitLab::Exporter::CLI do
    it "returns the rigth parser" do
      expect(GitLab::Exporter::CLI.for("git")).to be(GitLab::Exporter::CLI::GIT)
    end

    it "returns a null parser if it is not found" do
      expect(GitLab::Exporter::CLI.for("invalid")).to be(GitLab::Exporter::CLI::NullRunner)
    end
  end

  describe GitLab::Exporter::CLI::GIT do
    let(:output) { StringIO.new }
    it "works end to end" do
      args = CLIArgs.new([repos.cloned_repo, output])
      ssh = GitLab::Exporter::CLI::GIT.new(args)
      ssh.run
      output.rewind
      expect(output.read).to match(/git_push_time_milliseconds \d+ \d+/)
    end
  end
end

describe GitLab::Exporter::CLI::Server do
  context "extra-config-command is passed" do
    let(:argv) do
      ["-c", "spec/fixtures/config.yml", "--extra-config-command", extra_config_command]
        .extend(OptionParser::Arguable)
    end
    let(:extra_config_command) { "vault kv get top-secrets" }
    let(:server_cmd) { described_class.new(argv) }

    before do
      allow(server_cmd).to receive(:run_extra_config_command).and_return(<<~YAML
        probes:
          sidekiq:
            methods:
              - probe_workers
            opts:
              redis_url: redis://hunter1@localhost:9765
          database:
            opts:
              connection_string: postgres://db-admin:hunter1@localhost:6543/main-db
      YAML
                                                                        )
    end

    it "merges the returned YAML from the command with the passed config" do
      expect(server_cmd.merged_config).to eq({
                                               probes: {
                                                 sidekiq: {
                                                   methods: %w[probe_stats probe_workers],
                                                   opts: {
                                                     redis_url: "redis://hunter1@localhost:9765"
                                                   }
                                                 },
                                                 database: {
                                                   methods: ["probe_db"],
                                                   opts: {
                                                     connection_string:
                                                      "postgres://db-admin:hunter1@localhost:6543/main-db"
                                                   }
                                                 }
                                               }
                                             })
    end
  end
end
