require "spec_helper"
require "gitlab_exporter/database/zoekt"

describe GitLab::Exporter::Database::ZoektCollector do
  let(:connection_pool) { double("connection pool") }
  let(:connection) { double("connection") }
  let(:zoekt_tasks_processing_query) { described_class::ZOEKT_TASKS_PROCESSING_QUERY }
  let(:zoekt_nodes_query) { described_class::ZOEKT_NODES_QUERY }
  let(:zoekt_nodes_query_results) { [{ "id" => "1", "schema_version" => "2302", "node_name" => "foo" }] }
  let(:zoekt_enabled_query) { described_class::ZOEKT_ENABLED_QUERY }
  let(:zoekt_repository_schema_version_query) { described_class::ZOEKT_REPOSITORY_SCHEMA_VERSION_QUERY }
  let(:zoekt_nodes_status_query) { described_class::ZOEKT_NODES_STATUS_QUERY }
  let(:zoekt_nodes_status_query_results) { [{ "id" => "1", "name" => "foo", "status" => "1" }] }
  let(:zoekt_node_storage_query) { described_class::ZOEKT_NODE_STORAGE_QUERY }
  let(:zoekt_node_storage_query_results) do
    [{ "id" => "1", "node_name" => "foo", "unclaimed_storage_bytes" => "1000000", "storage_percent_used" => "0.75" }]
  end
  let(:zoekt_repositories_state_query) { described_class::ZOEKT_REPOSITORIES_STATE_QUERY }
  let(:zoekt_repositories_state_query_results) do
    [{ "state" => "0", "count" => "5" }, { "state" => "10", "count" => "15" }]
  end
  let(:zoekt_indices_state_query) { described_class::ZOEKT_INDICES_STATE_QUERY }
  let(:zoekt_indices_state_query_results) do
    [{ "state" => "0", "count" => "3" }, { "state" => "1", "count" => "7" }]
  end
  let(:zoekt_indices_watermark_query) { described_class::ZOEKT_INDICES_WATERMARK_QUERY }
  let(:zoekt_indices_watermark_query_results) do
    [{ "watermark_level" => "healthy", "count" => "8" }, { "watermark_level" => "warning", "count" => "2" }]
  end

  let(:zoekt_repository_schema_version_query_results) { [{ "count" => "1" }] }

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
    let(:zoekt_tasks_processing_query_results) do
      [
        { "node_id" => "1", "node_name" => "zoekt-1", "task_count" => "5" },
        { "node_id" => "2", "node_name" => "zoekt-2", "task_count" => "10" }
      ]
    end

    let(:zoekt_repositories_schema_version_query_results) do
      Set.new(
        [{ target_schema_version: "2302", zoekt_node_id: "1", zoekt_node_name: "foo", unfinished_repository_count: 1 }]
      )
    end

    let(:result) do
      {
        repositories_schema_version_query_result: zoekt_repositories_schema_version_query_results,
        task_processing_query_result: zoekt_tasks_processing_query_results,
        zoekt_nodes_status_query_result: zoekt_nodes_status_query_results,
        node_storage_query_result: zoekt_node_storage_query_results,
        repositories_state_query_result: zoekt_repositories_state_query_results,
        indices_state_query_result: zoekt_indices_state_query_results,
        indices_watermark_query_result: zoekt_indices_watermark_query_results
      }
    end

    before do
      allow(Time).to receive(:now).and_return(frozen_time)
    end

    context "when zoekt is not enabled" do
      before do
        stub_zoekt_not_enabled
      end

      it "returns {}" do
        expect(collector.run).to eq({})
      end
    end

    context "when zoekt is enabled" do
      before do
        stub_zoekt_enabled
      end

      it "executes the query with correct params" do
        expect(connection).to receive(:exec_params).with(zoekt_tasks_processing_query, [frozen_time])
                                                   .and_return(zoekt_tasks_processing_query_results)
        expect(connection).to receive(:exec_params).with(zoekt_nodes_query, [])
                                                   .and_return(zoekt_nodes_query_results)
        expect(connection).to receive(:exec_params).with(zoekt_repository_schema_version_query, %w[1 2302])
                                                   .and_return(zoekt_repository_schema_version_query_results)
        expect(connection).to receive(:exec_params).with(zoekt_nodes_status_query, [])
                                                   .and_return(zoekt_nodes_status_query_results)
        expect(connection).to receive(:exec_params).with(zoekt_node_storage_query, [])
                                                   .and_return(zoekt_node_storage_query_results)
        expect(connection).to receive(:exec_params).with(zoekt_repositories_state_query, [])
                                                   .and_return(zoekt_repositories_state_query_results)
        expect(connection).to receive(:exec_params).with(zoekt_indices_state_query, [])
                                                   .and_return(zoekt_indices_state_query_results)
        expect(connection).to receive(:exec_params).with(zoekt_indices_watermark_query, [])
                                                   .and_return(zoekt_indices_watermark_query_results)

        expect(collector.run).to eq(result)
      end

      context "when PG::UndefinedTable is raised" do
        it "does not includes the key which got the exception" do
          allow(connection).to receive(:exec_params).with(zoekt_tasks_processing_query, [frozen_time])
                                                    .and_raise(PG::UndefinedTable)
          allow(connection).to receive(:exec_params).with(zoekt_nodes_query, [])
                                                    .and_raise(PG::UndefinedTable)
          allow(connection).to receive(:exec_params).with(zoekt_nodes_status_query, [])
                                                    .and_raise(PG::UndefinedTable)
          allow(connection).to receive(:exec_params).with(zoekt_node_storage_query, [])
                                                    .and_raise(PG::UndefinedTable)
          allow(connection).to receive(:exec_params).with(zoekt_repositories_state_query, [])
                                                    .and_raise(PG::UndefinedTable)
          allow(connection).to receive(:exec_params).with(zoekt_indices_state_query, [])
                                                    .and_raise(PG::UndefinedTable)
          allow(connection).to receive(:exec_params).with(zoekt_indices_watermark_query, [])
                                                    .and_raise(PG::UndefinedTable)

          expect(collector.run).to eq({})
        end
      end

      context "when PG::UndefinedColumn is raised" do
        it "does not includes the key which got the exception" do
          allow(connection).to receive(:exec_params).with(zoekt_tasks_processing_query, [frozen_time])
                                                    .and_return(zoekt_tasks_processing_query_results)
          expect(connection).to receive(:exec_params).with(zoekt_nodes_query, [])
                                                     .and_return(zoekt_nodes_query_results)
          expect(connection).to receive(:exec_params).with(zoekt_repository_schema_version_query, %w[1 2302])
                                                     .and_raise(PG::UndefinedTable)
          expect(connection).to receive(:exec_params).with(zoekt_nodes_status_query, []).and_raise(PG::UndefinedTable)
          expect(connection).to receive(:exec_params).with(zoekt_node_storage_query, []).and_raise(PG::UndefinedColumn)
          expect(connection).to receive(:exec_params).with(zoekt_repositories_state_query, [])
                                                     .and_raise(PG::UndefinedColumn)
          expect(connection).to receive(:exec_params).with(zoekt_indices_state_query, [])
                                                     .and_raise(PG::UndefinedColumn)
          expect(connection).to receive(:exec_params).with(zoekt_indices_watermark_query, [])
                                                     .and_raise(PG::UndefinedColumn)

          expect(collector.run).to eq({ task_processing_query_result: zoekt_tasks_processing_query_results })
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
    {
      repositories_schema_version_query_result: Set.new(
        [{ target_schema_version: "2302", zoekt_node_id: "1", unfinished_repository_count: 1, zoekt_node_name: "foo" }]
      ),
      task_processing_query_result: [
        { "node_id" => "1", "node_name" => "zoekt-1", "task_count" => "5" },
        { "node_id" => "2", "node_name" => "zoekt-2", "task_count" => "10" }
      ],
      node_storage_query_result: [
        {
          "id" => "1", "node_name" => "zoekt-1", "unclaimed_storage_bytes" => "1000000",
          "storage_percent_used" => "0.75"
        },
        {
          "id" => "2", "node_name" => "zoekt-2", "unclaimed_storage_bytes" => "2000000",
          "storage_percent_used" => "0.50"
        }
      ],
      repositories_state_query_result: [
        { "state" => "0", "count" => "5" },
        { "state" => "10", "count" => "15" }
      ],
      indices_state_query_result: [
        { "state" => "0", "count" => "3" },
        { "state" => "1", "count" => "7" }
      ],
      indices_watermark_query_result: [
        { "watermark_level" => "healthy", "count" => "8" },
        { "watermark_level" => "warning", "count" => "2" }
      ]
    }
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

      data[:task_processing_query_result].each do |node_data|
        expect(metrics).to receive(:add)
          .with(
            "search_zoekt_task_processing_queue_size",
            node_data["task_count"].to_i,
            node_name: node_data["node_name"],
            node_id: node_data["node_id"]
          )
      end

      data[:repositories_schema_version_query_result].each do |node_data|
        expect(metrics).to receive(:add)
          .with(
            "search_zoekt_repositories_schema_version_count",
            node_data[:unfinished_repository_count].to_i,
            target_schema_version: node_data[:target_schema_version],
            zoekt_node_id: node_data[:zoekt_node_id],
            zoekt_node_name: node_data[:zoekt_node_name]
          )
      end

      data[:node_storage_query_result].each do |node_data|
        expect(metrics).to receive(:add)
          .with(
            "search_zoekt_node_unclaimed_storage_bytes",
            node_data["unclaimed_storage_bytes"].to_i,
            zoekt_node_id: node_data["id"],
            zoekt_node_name: node_data["node_name"]
          )
        expect(metrics).to receive(:add)
          .with(
            "search_zoekt_node_storage_percent_used",
            node_data["storage_percent_used"].to_f,
            zoekt_node_id: node_data["id"],
            zoekt_node_name: node_data["node_name"]
          )
      end

      data[:repositories_state_query_result].each do |state_data|
        expect(metrics).to receive(:add)
          .with(
            "search_zoekt_repositories_states_total",
            state_data["count"].to_i,
            state: state_data["state"]
          )
      end

      data[:indices_state_query_result].each do |state_data|
        expect(metrics).to receive(:add)
          .with(
            "search_zoekt_indices_states",
            state_data["count"].to_i,
            state: state_data["state"]
          )
      end

      data[:indices_watermark_query_result].each do |watermark_data|
        expect(metrics).to receive(:add)
          .with(
            "search_zoekt_indices_watermark_levels",
            watermark_data["count"].to_i,
            watermark_level: watermark_data["watermark_level"]
          )
      end

      probe_db
    end
  end
end
