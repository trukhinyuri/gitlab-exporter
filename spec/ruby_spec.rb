require "spec_helper"
require "gitlab_exporter/ruby"
require "gitlab_exporter/prober"

describe GitLab::Exporter::RubyProber do
  let(:prober) { GitLab::Exporter::Prober.new(options) }

  let(:options) do
    {
      ruby: {
        class_name: described_class.to_s,
        methods: %w[probe_gc],
        opts: { quantiles: false }
      }
    }
  end

  it "probes and returns GC stats" do
    prober.probe_all

    output = StringIO.new
    prober.write_to(output)
    expect(output.string).to match(/ruby_gc_stat_count \d+ \d+/)
  end
end
