require "spec_helper"

describe GitLab::Exporter::TimeTracker do
  it "tracks execution time" do
    expect(subject.track { sleep 0.1 }.time).to satisfy { |v| v >= 0.1 }
  end
end

describe GitLab::Exporter::Utils do
  it "excludes extraneous PIDs" do
    allow(described_class).to receive(:exec_pgrep).and_return("12345 my-process\n98765 sh\n")

    expect(described_class.pgrep("some-process")).to eq(["12345"])
  end

  it "handles invalid UTF-8 byte sequences in pgrep output" do
    raw_output = (+"12345 git commit -m \xFF\xFE\n98765 sh\n").force_encoding(Encoding::UTF_8)
    allow(described_class).to receive(:exec_pgrep).and_return(raw_output)

    expect(described_class.pgrep("git")).to eq(["12345"])
  end
end
