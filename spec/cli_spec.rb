require "spec_helper"
require "gitlab_exporter/cli"

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
