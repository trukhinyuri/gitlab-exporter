require "spec_helper"
require "stringio"
require "gitlab_exporter/process"

describe GitLab::Exporter::ProcessStats do
  let(:pid) { "12345" }
  let(:raw_stat) do
    fields = Array.new(44, "0")
    fields[0] = pid
    fields[1] = "(git-\xFF\xFE-worker)"
    fields[2] = "S"
    fields[13] = "150"
    fields[14] = "50"
    fields[21] = "1000"
    fields[22] = "4096000"
    fields[23] = "256"
    (+"#{fields.join(' ')}\n").force_encoding(Encoding::UTF_8)
  end

  before do
    allow(File).to receive(:read).with("/proc/#{pid}/stat").and_return(raw_stat)
  end

  it "scrubs invalid UTF-8 bytes in /proc/<pid>/stat and parses stats" do
    stats = described_class.new(pid)

    expect(stats).to be_valid
    expect(stats.vsize).to eq(4_096_000)
    expect(stats.rss).to eq(256 * 4096)
  end
end

describe GitLab::Exporter::ProcessProber do
  let(:pid) { "12345" }
  let(:output) { StringIO.new }
  let(:raw_stat) do
    fields = Array.new(44, "0")
    fields[0] = pid
    fields[1] = "(git-\xFF\xFE-worker)"
    fields[2] = "S"
    fields[13] = "150"
    fields[14] = "50"
    fields[21] = "1000"
    fields[22] = "4096000"
    fields[23] = "256"
    (+"#{fields.join(' ')}\n").force_encoding(Encoding::UTF_8)
  end

  before do
    allow(File).to receive(:read).with("/proc/#{pid}/stat").and_return(raw_stat)
  end

  it "probes process stats when /proc/<pid>/stat contains invalid UTF-8 bytes" do
    prober = described_class.new(name: "git", pid_or_pattern: pid)
    expect { prober.probe_stat.write_to(output) }.not_to raise_error
    expect(output.string).to include("process_virtual_memory_bytes{name=\"git\",pid=\"12345\"} 4096000")
    expect(output.string).to include("process_resident_memory_bytes{name=\"git\",pid=\"12345\"} 1048576")
  end
end
