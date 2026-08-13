require "spec_helper"
require "gitlab_exporter/database/tuple_stats"

describe GitLab::Exporter::Database::TuplesProber do
  let(:opts) { { connection_string: "" } }
  let(:metrics) { double("PrometheusMetrics", add: nil) }
  let(:collector) { double("TupleStatsCollector", run: data) }

  before do
    allow(GitLab::Exporter::Database::TupleStatsCollector).to receive(:new).and_return(collector)
  end

  describe "#probe_db" do
    subject { described_class.new(metrics: metrics, **opts).probe_db }

    context "when the connection casts columns to native Integer (PG::BasicTypeMapForResults)" do
      let(:data) { { "projects" => { "seq_tup_read" => 42, "n_dead_tup" => 0 } } }

      it "still records a metric for every column" do
        expect(metrics).to receive(:add)
          .with("gitlab_database_stat_table_seq_tup_read", 42.0, table_name: "projects")
        expect(metrics).to receive(:add)
          .with("gitlab_database_stat_table_n_dead_tup", 0.0, table_name: "projects")

        subject
      end
    end

    context "when the connection returns unmapped string values" do
      let(:data) { { "projects" => { "seq_tup_read" => "42" } } }

      it "records a metric" do
        expect(metrics).to receive(:add)
          .with("gitlab_database_stat_table_seq_tup_read", 42.0, table_name: "projects")

        subject
      end
    end
  end
end
