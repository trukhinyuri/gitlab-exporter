require "spec_helper"
require "open3"
require "tmpdir"

describe GitLab::Monitor::Git do

  it "fails with an invalid repository" do
    repo = Dir.mktmpdir
    Dir.rmdir(repo)
    expect{GitLab::Monitor::Git.new(repo)}.to raise_error(/Repository #{repo} does not exists/)
  end

  context "with an actual git repo" do
    let (:origin) {
      path = Dir.mktmpdir
      Open3.capture3("git init", chdir: path)
      Open3.capture3("git commit --allow-empty -m 'Beep'", chdir: path)
      Open3.capture3("git checkout -b other", chdir: path)
      path
    }
    let(:repo) {
      path = Dir.mktmpdir
      Dir.rmdir(path)
      Open3.capture3("git clone #{origin} #{path}")
      Open3.capture3("git checkout master", chdir: path)
      path
    }

    it "builds with a repo folder" do
      expect(GitLab::Monitor::Git.new(repo)).to be
    end

    it "pulls correctly" do
      expect(GitLab::Monitor::Git.new(repo).pull.time).to satisfy {|v| v >= 0}
    end

    it "pushes correctly" do
      expect(GitLab::Monitor::Git.new(repo).push.time).to satisfy {|v| v >= 0}
    end

    after {
      FileUtils.rm_r(repo)
      FileUtils.rm_r(origin)
    }
  end
end
