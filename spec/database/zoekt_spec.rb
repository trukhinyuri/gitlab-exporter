require "spec_helper"
require "gitlab_exporter/database/zoekt"

describe GitLab::Exporter::Database::ZoektCollector do
  let(:connection_pool) { double("connection pool") }
  let(:connection) { double("connection") }
  let(:query) { described_class::QUERY }
  let(:zoekt_enabled_query) { described_class::ZOEKT_ENABLED_QUERY }

  subject(:collector) { described_class.new(connection_string: "host=localhost") }

  before do
    allow(collector).to receive(:connection_pool).and_return(connection_pool)
    allow(connection_pool).to receive(:with).and_yield(connection)
    # allow(Time).to receive(:now).and_return(time_now)
  end

  def stub_zoekt_enabled
    allow(connection).to receive(:exec).with(zoekt_enabled_query).and_return([{ "zoekt_indexing_enabled" => "true" }])
  end

  def stub_zoekt_not_enabled
    allow(connection).to receive(:exec).with(zoekt_enabled_query).and_return([{ "zoekt_indexing_enabled" => "false" }])
  end

  describe "#run" do
    let(:zoekt_enabled_results) {}
    let(:frozen_time) { Time.new(2023, 1, 1, 0, 0, 0, 0) }
    let(:query_results) do
      [
        { "node_id" => "1", "node_name" => "zoekt-1", "task_count" => "5" },
        { "node_id" => "2", "node_name" => "zoekt-2", "task_count" => "10" }
      ]
    end

    before do
      allow(Time).to receive(:now).and_return(frozen_time)
    end

    context "when zoekt is not enabled" do
      before do
        stub_zoekt_not_enabled
      end

      it "returns nil" do
        allow(connection).to receive(:exec_params).with(query, frozen_time).and_raise(PG::UndefinedTable)

        expect(collector.run).to be_nil
      end
    end

    context "when zoekt is enabled" do
      before do
        stub_zoekt_enabled
      end

      it "executes the query with the current time" do
        expect(connection).to receive(:exec_params).with(query, [frozen_time]).and_return(query_results)

        expect(collector.run).to eq(query_results)
      end

      context "when PG::UndefinedTable is raised" do
        it "returns nil" do
          allow(connection).to receive(:exec_params).with(query, [frozen_time]).and_raise(PG::UndefinedTable)

          expect(collector.run).to be_nil
        end
      end

      context "when PG::UndefinedColumn is raised" do
        it "returns nil" do
          allow(connection).to receive(:exec_params).with(query, [frozen_time]).and_raise(PG::UndefinedColumn)

          expect(collector.run).to be_nil
        end
      end
    end
  end

  describe "#zoekt_indexing_enabled?" do
    it "returns true when zoekt is enabled" do
      expect(connection).to receive(:exec)
        .with(zoekt_enabled_query).and_return([{ "zoekt_indexing_enabled" => "true" }])

      expect(subject.send(:zoekt_indexing_enabled?)).to eq(true)
    end

    it "returns false when PG::UndefinedColumn is raised" do
      expect(connection).to receive(:exec).with(zoekt_enabled_query).and_raise(PG::UndefinedColumn)

      expect(subject.send(:zoekt_indexing_enabled?)).to eq(false)
    end
  end
end

describe GitLab::Exporter::Database::ZoektProber do
  let(:opts) { { connection_string: "host=localhost" } }
  let(:metrics) { double("PrometheusMetrics", add: nil) }
  let(:collector) { double(GitLab::Exporter::Database::ZoektCollector, run: data) }
  let(:data) do
    [
      { "node_id" => "1", "node_name" => "zoekt-1", "task_count" => "5" },
      { "node_id" => "2", "node_name" => "zoekt-2", "task_count" => "10" }
    ]
  end

  describe "#probe_db" do
    before do
      allow(collector).to receive(:connected?).and_return(true)
    end

    subject(:probe_db) do
      described_class.new(metrics: metrics, collector: collector, **opts).probe_db
    end

    it "invokes the collector" do
      expect(collector).to receive(:run)

      probe_db
    end

    it "adds metrics for each node" do
      expect(collector).to receive(:run).and_return(data)

      data.each do |node_data|
        expect(metrics).to receive(:add)
          .with("search_zoekt_task_processing_queue_size",
                node_data["task_count"].to_i,
                node_name: node_data["node_name"],
                node_id: node_data["node_id"])
      end

      probe_db
    end
  end
end
