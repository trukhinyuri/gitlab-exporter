require "spec_helper"
require "stringio"
require "gitlab_monitor/cli"

context "An invalid repository" do
  describe GitLab::Monitor::Git do
    it "fails with an invalid repository" do
      repo = Dir.mktmpdir
      Dir.rmdir(repo)
      expect { GitLab::Monitor::Git.new(repo) }.to raise_error(/Repository #{repo} does not exists/)
    end
  end
end

context "With valid pair of repositories" do
  let(:repos) { GitRepoBuilder.new }

  after do
    repos.cleanup
  end

  describe GitLab::Monitor::Git do
    it "builds with a repo folder" do
      expect(GitLab::Monitor::Git.new(repos.cloned_repo)).to be
    end

    it "pulls correctly" do
      expect(GitLab::Monitor::Git.new(repos.cloned_repo).pull.time).to satisfy { |v| v >= 0 }
    end

    it "pushes correctly" do
      expect(GitLab::Monitor::Git.new(repos.cloned_repo).push.time).to satisfy { |v| v >= 0 }
    end
  end

  describe GitLab::Monitor::GitProber do
    let(:options) { GitProberOptions.new(repos.cloned_repo, {}) }
    let(:output) { StringIO.new }

    it "probes and monitors a pull" do
      prober = GitLab::Monitor::GitProber.new(options)
      prober.probe_pull.write_to(output)
      expect(output.string).to match(/git_pull_time_milliseconds \d+ \d+/)
    end

    it "probes and monitors a push" do
      prober = GitLab::Monitor::GitProber.new(options)
      prober.probe_push.write_to(output)
      expect(output.string).to match(/git_push_time_milliseconds \d+ \d+/)
    end
  end
end
