require "spec_helper"
require "gitlab_monitor/memstats"

describe GitLab::Monitor::MemStats do
  let(:pid) { 100 }
  let(:smaps_data) { File.open("spec/fixtures/smaps/sample.txt") }

  subject { described_class::Aggregator.new(pid) }

  before do
    expect(File).to receive(:open).with("/proc/#{pid}/smaps").and_yield(smaps_data)
  end

  it "parses the data properly" do
    expect(subject.valid?).to be_truthy

    nonzero_fields = %w(size rss shared_clean shared_dirty private_dirty pss)
    zero_fields = %w(private_clean swap)

    nonzero_fields.each do |field|
      expect(subject.totals[field]).to be > 0 # rubocop:disable Style/NumericPredicate
    end

    zero_fields.each do |field|
      expect(subject.totals[field]).to eq(0)
    end
  end
end
