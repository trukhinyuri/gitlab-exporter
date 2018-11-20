require "spec_helper"

describe GitLab::Monitor::TimeTracker do
  it "tracks execution time" do
    expect(subject.track { sleep 0.1 }.time).to satisfy { |v| v >= 0.1 }
  end
end

describe GitLab::Monitor::Utils do
  it "excludes extraneous PIDs" do
    allow(described_class).to receive(:exec_pgrep).and_return("12345 my-process\n98765 sh\n")

    expect(described_class.pgrep("some-process")).to eq(["12345"])
  end
end
