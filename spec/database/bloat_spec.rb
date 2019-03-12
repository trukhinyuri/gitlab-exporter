require "spec_helper"
require "gitlab_monitor/database/bloat"

describe GitLab::Monitor::Database::BloatCollector do
  let(:connection_pool) { double("connection pool") }
  let(:connection) { double("connection") }

  subject { described_class.new(connection_string: "").run(type) }
  let(:type) { :btree }
  let(:query) { "select something" }

  before do
    allow_any_instance_of(described_class).to receive(:connection_pool).and_return(connection_pool)
    allow(connection_pool).to receive(:with).and_yield(connection)
  end

  it "converts query results into a hash" do
    row1 = { "object_name" => "o", "more_stuff" => 1 }
    row2 = { "object_name" => "a", "more_stuff" => 2 }

    expect(File).to receive(:read).and_return(query)
    expect(connection).to receive(:exec).with(query).and_return([row1, row2])

    expect(subject).to eq("o" => row1, "a" => row2)
  end
end

describe GitLab::Monitor::Database::BloatProber do
  let(:opts) { { bloat_types: %i(btree table) } }
  let(:metrics) { double("PrometheusMetrics", add: nil) }
  let(:collector) { double("BloatCollector", run: data) }

  let(:data) do
    {
      "object" => {
        "object_name" => "object",
        "bloat_ratio" => 1,
        "bloat_size" => 2,
        "extra_size" => 3,
        "real_size" => 4
      }
    }
  end

  describe"#probe_db" do
    subject { described_class.new(opts, metrics: metrics, collector: collector).probe_db }

    it "invokes the collector for each bloat type" do
      expect(collector).to receive(:run).with(:btree)
      expect(collector).to receive(:run).with(:table)

      subject
    end

    it "adds bloat_ratio metric" do
      opts[:bloat_types].each do |type|
        expect(metrics).to receive(:add).with("gitlab_database_bloat_#{type}_bloat_ratio", 1, query_name: "object")
      end

      subject
    end

    it "adds bloat_size metric" do
      opts[:bloat_types].each do |type|
        expect(metrics).to receive(:add).with("gitlab_database_bloat_#{type}_bloat_size", 2, query_name: "object")
      end

      subject
    end

    it "adds extra_size metric" do
      opts[:bloat_types].each do |type|
        expect(metrics).to receive(:add).with("gitlab_database_bloat_#{type}_extra_size", 3, query_name: "object")
      end

      subject
    end

    it "adds real_size metric" do
      opts[:bloat_types].each do |type|
        expect(metrics).to receive(:add).with("gitlab_database_bloat_#{type}_real_size", 4, query_name: "object")
      end

      subject
    end
  end

  context "#write_to" do
    let(:target) { double }
    let(:metrics) { double("PrometheusMetrics", to_s: double) }
    subject { described_class.new(opts, metrics: metrics).write_to(target) }

    it "writes to given target" do
      expect(target).to receive(:write).with(metrics.to_s)

      subject
    end
  end
end
