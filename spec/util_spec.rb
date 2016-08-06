require "spec_helper"
require "open3"
require "tmpdir"

describe GitLab::Monitor::TimeTracker do
  it "tracks execution time" do
    expect(subject.track { sleep 0.1 }.time).to satisfy {|v| v >= 0.1}
  end
end

describe GitLab::Monitor::PrometheusMetrics do
  it "supports simple metrics" do
    expect(subject.add("mymetric", 1.1).to_s).to match(/mymetric 1.1 \d*$/)
  end

  it "supports metrics with one label" do
    expect(subject.add("mymetric", 1.2, mylabel: "x").to_s).to match(/mymetric{mylabel="x"} 1.2 \d*$/)
  end

  it "supports metrics with many labels" do
    expect(subject.add("mymetric", 1.3, mylabel: "x", myotherlabel: "y").to_s).to match(
      /mymetric{mylabel="x",myotherlabel="y"} 1.3 \d*$/)
  end
end

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
