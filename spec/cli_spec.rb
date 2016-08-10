require "spec_helper"
require "gitlab_monitor/cli"

context "With valid pair of repositories" do
  let(:repos) { GitRepoBuilder.new }

  after do
    repos.cleanup
  end

  describe GitLab::Monitor::CLI do
    it "returns the rigth parser" do
      expect(GitLab::Monitor::CLI.for("git")).to be(GitLab::Monitor::CLI::GIT)
    end

    it "returns a null parser if it is not found" do
      expect(GitLab::Monitor::CLI.for("invalid")).to be(GitLab::Monitor::CLI::NullRunner)
    end
  end

  describe GitLab::Monitor::CLI::GIT do
    let(:output) { StringIO.new }
    it "works end to end" do
      args = CLIArgs.new([repos.cloned_repo, output])
      ssh = GitLab::Monitor::CLI::GIT.new(args)
      ssh.run
      output.rewind
      expect(output.read).to match(/git_push_time_milliseconds \d+ \d+/)
    end
  end
end
