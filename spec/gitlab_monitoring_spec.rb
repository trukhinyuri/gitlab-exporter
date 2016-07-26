require "spec_helper"
require "gitlab_monitoring"

describe GitLab::TimeTracker do
  it "tracks execution time" do
    expect(subject.track { sleep 0.1 }).to satisfy {|v| v >= 0.1}
  end
end
