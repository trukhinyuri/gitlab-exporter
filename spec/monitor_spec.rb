require "spec_helper"

describe GitLab::TimeTracker do
  let(:tracker) { subject.new }
  it "tracks execution time" do
    expect(tracker.track { sleep 0.1 }).to match {|v| v >= 0.1}
  end
end
