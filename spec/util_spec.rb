require "spec_helper"

describe GitLab::Monitor::TimeTracker do
  it "tracks execution time" do
    expect(subject.track { sleep 0.1 }.time).to satisfy {|v| v >= 0.1}
  end
end
