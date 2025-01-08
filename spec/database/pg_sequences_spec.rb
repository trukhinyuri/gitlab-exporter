require "spec_helper"
require "gitlab_exporter/database/pg_sequences"

describe GitLab::Exporter::Database::PgSequencesCollector do
  subject { described_class.new(connection_string: "") }

  let(:connection_pool) { double("connection pool") }
  let(:connection) { double("connection", exec: query_result) }
  let(:type) { :btree }
  let(:query_result) do
    [
      {
        "schemaname" => "public",
        "sequencename" => "seq_one",
        "fully_qualified_sequencename" => "public.seq_one",
        "min_value" => 1,
        "max_value" => 9_223_372_036_854_775_807,
        "current_value" => 6_223_372_036_854_745_121,
        "saturation_ratio" => 0.6747e2
      },
      {
        "schemaname" => "public",
        "sequencename" => "seq_two",
        "fully_qualified_sequencename" => "public.seq_two",
        "min_value" => 1,
        "max_value" => 9_223_372_036_854_775_807,
        "current_value" => nil,
        "saturation_ratio" => 0.0
      }
    ]
  end

  before do
    allow_any_instance_of(described_class).to receive(:connection_pool).and_return(connection_pool)
    allow(connection_pool).to receive(:with).and_yield(connection)
  end

  it "converts query results into a hash" do
    expect(subject.run).to(
      eq(
        "public.seq_one" => {
          "schemaname" => "public",
          "sequencename" => "seq_one",
          "min_value" => 1,
          "max_value" => 9_223_372_036_854_775_807,
          "current_value" => 6_223_372_036_854_745_121,
          "saturation_ratio" => 0.6747e2
        },
        "public.seq_two" => {
          "schemaname" => "public",
          "sequencename" => "seq_two",
          "min_value" => 1,
          "max_value" => 9_223_372_036_854_775_807,
          "current_value" => nil,
          "saturation_ratio" => 0.0
        }
      )
    )
  end
end

describe GitLab::Exporter::Database::PgSequencesProber do
  subject(:prober) { described_class.new(metrics: metrics, connection_string: "") }

  let(:metrics) { double("PrometheusMetrics", add: nil) }
  let(:collector) { double("PgSequencesCollector", run: data) }
  let(:data) do
    {
      "public.seq_one" => {
        "schemaname" => "public",
        "sequencename" => "seq_one",
        "min_value" => 1,
        "max_value" => 10,
        "current_value" => 2,
        "saturation_ratio" => 0.2
      }
    }
  end

  describe "#probe_db" do
    before do
      allow(GitLab::Exporter::Database::PgSequencesCollector).to receive(:new).and_return(collector)
    end

    it "properly invokes the collector" do
      expect(collector).to receive(:run)

      prober.probe_db
    end

    it "adds min_value metric" do
      expect(metrics).to(
        receive(:add).with(
          "gitlab_pg_sequences_min_value",
          1.0,
          schemaname: "public",
          sequencename: "seq_one",
          fully_qualified_sequencename: "public.seq_one"
        )
      )

      prober.probe_db
    end

    it "adds max_value metric" do
      expect(metrics).to(
        receive(:add).with(
          "gitlab_pg_sequences_max_value",
          10.0,
          schemaname: "public",
          sequencename: "seq_one",
          fully_qualified_sequencename: "public.seq_one"
        )
      )

      prober.probe_db
    end

    it "adds current_value metric" do
      expect(metrics).to(
        receive(:add).with(
          "gitlab_pg_sequences_current_value",
          2.0,
          schemaname: "public",
          sequencename: "seq_one",
          fully_qualified_sequencename: "public.seq_one"
        )
      )

      prober.probe_db
    end
  end
end
