require "spec_helper"
require "stringio"

describe GitLab::Monitor::Git do
  it "fails with an invalid repository" do
    repo = Dir.mktmpdir
    Dir.rmdir(repo)
    expect{GitLab::Monitor::Git.new(repo)}.to raise_error(/Repository #{repo} does not exists/)
  end

  context "with an actual git repo" do
    let (:repos) { GitRepoBuilder.new }

    it "builds with a repo folder" do
      expect(GitLab::Monitor::Git.new(repos.clone)).to be
    end

    it "pulls correctly" do
      expect(GitLab::Monitor::Git.new(repos.clone).pull.time).to satisfy {|v| v >= 0}
    end

    it "pushes correctly" do
      expect(GitLab::Monitor::Git.new(repos.clone).push.time).to satisfy {|v| v >= 0}
    end

    after { repos.cleanup }
  end
end

GitProberOptions = Struct.new(:repo_path, :labels) do
  attr_reader :output

  def target
    buffer = StringIO.new
    yield buffer
    buffer.rewind
    @output = buffer.read
  end
end

describe GitLab::Monitor::GitProber do
  let (:repos) { GitRepoBuilder.new }
  let (:options) { GitProberOptions.new(repos.clone, {}) }

  it "probes and monitors a pull" do
    prober = GitLab::Monitor::GitProber.new(options)
    prober.probe_pull.write
    expect(options.output).to match(/git_pull_time_milliseconds \d+ \d+/)
  end

  it "probes and monitors a push" do
    prober = GitLab::Monitor::GitProber.new(options)
    prober.probe_push.write
    expect(options.output).to match(/git_push_time_milliseconds \d+ \d+/)
  end

  after { repos.cleanup }
end
