require "spec_helper"
require "gitlab_exporter/database/geo_node_status"

describe GitLab::Exporter::Database::GeoNodeStatusCollector do
  let(:connection_pool) { double("connection pool") }
  let(:connection) { double("connection") }
  let(:results) { [{ "geo_node_name" => "secondary", "status" => { "projects_count" => 12 } }] }

  subject(:collector) { described_class.new(connection_string: "host=localhost") }

  before do
    allow(collector).to receive(:connection_pool).and_return(connection_pool)
    allow(connection_pool).to receive(:with).and_yield(connection)
  end

  describe "QUERY" do
    it "selects all required status columns, timestamps, and node name" do
      expect(described_class::QUERY).to include("geo_nodes.name AS geo_node_name")
      expect(described_class::QUERY).to include("geo_node_statuses.db_replication_lag_seconds")
      expect(described_class::QUERY).to include("geo_node_statuses.replication_slots_count")
      expect(described_class::QUERY).to include("geo_node_statuses.replication_slots_used_count")
      expect(described_class::QUERY).to include("geo_node_statuses.replication_slots_max_retained_wal_bytes")
      expect(described_class::QUERY).to include("geo_node_statuses.last_event_id")
      expect(described_class::QUERY).to include("geo_node_statuses.cursor_last_event_id")
      expect(described_class::QUERY).to include("geo_node_statuses.status")
      expect(described_class::QUERY).to include(
        "EXTRACT(EPOCH FROM geo_node_statuses.last_event_date)::bigint AS last_event_timestamp"
      )
      expect(described_class::QUERY).to include(
        "EXTRACT(EPOCH FROM geo_node_statuses.cursor_last_event_date)::bigint AS cursor_last_event_timestamp"
      )
      expect(described_class::QUERY).to include(
        "EXTRACT(EPOCH FROM geo_node_statuses.last_successful_status_check_at)::bigint"
      )
    end
  end

  describe "#run" do
    it "queries enabled Geo nodes and returns their status data" do
      expect(connection).to receive(:exec).with(described_class::QUERY).and_return(results)

      expect(collector.run).to eq(results)
    end

    it "returns nil when Geo tables are unavailable" do
      allow(connection).to receive(:exec).and_raise(PG::UndefinedTable)

      expect(collector.run).to be_nil
    end
  end
end

describe GitLab::Exporter::Database::GeoNodeStatusProber do
  let(:writer) { StringIO.new }
  let(:metrics) { GitLab::Exporter::PrometheusMetrics.new(include_timestamp: false) }
  let(:collector) { double(GitLab::Exporter::Database::GeoNodeStatusCollector, run: results) }
  let(:results) do
    [
      {
        "geo_node_id" => 7,
        "geo_node_name" => "secondary",
        "db_replication_lag_seconds" => 4,
        "replication_slots_count" => 2,
        "replication_slots_used_count" => 1,
        "replication_slots_max_retained_wal_bytes" => 1024,
        "last_event_id" => 100,
        "cursor_last_event_id" => 98,
        "last_event_timestamp" => 1_750_000_100,
        "cursor_last_event_timestamp" => 1_750_000_090,
        "last_successful_status_check_timestamp" => 1_750_000_000,
        "status" => {
          "projects_count" => 12,
          "project_repositories_count" => 21,
          "projects_verification_total_count" => 8,
          "projects_synced_count" => 19,
          "projects_failed_count" => 2,
          "git_fetch_event_count_weekly" => 100,
          "container_repositories_replication_enabled" => true,
          "status_message" => "Healthy"
        }
      }
    ]
  end

  subject(:prober) { described_class.new(metrics: metrics, collector: collector) }

  describe "constants and data sources" do
    it "defines the expected COLUMN_METRICS corresponding to table columns" do
      expect(described_class::COLUMN_METRICS).to contain_exactly(
        "db_replication_lag_seconds",
        "replication_slots_count",
        "replication_slots_used_count",
        "replication_slots_max_retained_wal_bytes",
        "last_event_id",
        "cursor_last_event_id"
      )
    end

    it "defines the expected TIMESTAMP_METRICS corresponding to epoch extractions" do
      expect(described_class::TIMESTAMP_METRICS).to contain_exactly(
        "last_event_timestamp",
        "cursor_last_event_timestamp",
        "last_successful_status_check_timestamp"
      )
    end

    it "does not define CORE_STATUS_METRICS" do
      expect(described_class.const_defined?(:CORE_STATUS_METRICS)).to be false
    end

    it "does not emit column metrics if placed only inside status jsonb" do
      allow(collector).to receive(:run).and_return([
                                                     {
                                                       "geo_node_name" => "secondary",
                                                       "status" => {
                                                         "db_replication_lag_seconds" => 4,
                                                         "replication_slots_count" => 2,
                                                         "replication_slots_used_count" => 1,
                                                         "replication_slots_max_retained_wal_bytes" => 1024,
                                                         "last_event_id" => 100,
                                                         "cursor_last_event_id" => 98
                                                       }
                                                     }
                                                   ])

      prober.probe_db
      prober.write_to(writer)

      expect(writer.string).not_to include("geo_db_replication_lag_seconds")
      expect(writer.string).not_to include("geo_replication_slots")
      expect(writer.string).not_to include("geo_replication_slots_used")
      expect(writer.string).not_to include("geo_replication_slots_max_retained_wal_bytes")
      expect(writer.string).not_to include("geo_last_event_id")
      expect(writer.string).not_to include("geo_cursor_last_event_id")
    end

    it "does not emit replicator metrics if placed only in row columns outside status jsonb" do
      allow(collector).to receive(:run).and_return([
                                                     {
                                                       "geo_node_name" => "secondary",
                                                       "project_repositories_count" => 21,
                                                       "projects_synced_count" => 19,
                                                       "status" => {}
                                                     }
                                                   ])

      prober.probe_db
      prober.write_to(writer)

      expect(writer.string).not_to include("geo_repositories")
      expect(writer.string).not_to include("geo_projects_synced")
    end
  end

  describe "#probe_db" do
    it "exports integer Geo metrics with Rails-compatible names and site labels" do
      prober.probe_db
      prober.write_to(writer)
      labels = 'name="secondary",url="secondary"'

      expect(writer.string).to include("geo_db_replication_lag_seconds{#{labels}} 4")
      expect(writer.string).to include("# TYPE geo_db_replication_lag_seconds gauge")
      expect(writer.string).to include("geo_replication_slots{#{labels}} 2")
      expect(writer.string).to include("# TYPE geo_replication_slots gauge")
      expect(writer.string).to include("geo_replication_slots_used{#{labels}} 1")
      expect(writer.string).to include("# TYPE geo_replication_slots_used gauge")
      expect(writer.string).to include("geo_replication_slots_max_retained_wal_bytes{#{labels}} 1024")
      expect(writer.string).to include("# TYPE geo_replication_slots_max_retained_wal_bytes gauge")
      expect(writer.string).to include("geo_last_event_id{#{labels}} 100")
      expect(writer.string).to include("geo_cursor_last_event_id{#{labels}} 98")
      expect(writer.string).to include("geo_last_event_timestamp{#{labels}} 1750000100")
      expect(writer.string).to include("geo_cursor_last_event_timestamp{#{labels}} 1750000090")
      expect(writer.string).to include("geo_last_successful_status_check_timestamp{#{labels}} 1750000000")
      expect(writer.string).to include("geo_repositories{#{labels}} 21")
      expect(writer.string).to include("geo_projects_verification_total{#{labels}} 8")
      expect(writer.string).to include("geo_projects_synced{#{labels}} 19")
      expect(writer.string).to include("geo_projects_failed{#{labels}} 2")

      expect(writer.string).not_to include("event_log_max_id")
      expect(writer.string).not_to include("geo_projects{")
      expect(writer.string).not_to include("geo_git_fetch_event")
      expect(writer.string).not_to include("container_repositories_replication_enabled")
      expect(writer.string).not_to include("status_message")
    end

    it "handles nil column values gracefully" do
      allow(collector).to receive(:run).and_return([
                                                     {
                                                       "geo_node_name" => "secondary",
                                                       "db_replication_lag_seconds" => nil,
                                                       "replication_slots_count" => nil,
                                                       "status" => { "project_repositories_count" => 5 }
                                                     }
                                                   ])

      prober.probe_db
      prober.write_to(writer)

      expect(writer.string).not_to include("geo_db_replication_lag_seconds")
      expect(writer.string).not_to include("geo_replication_slots")
      expect(writer.string).to include('geo_repositories{name="secondary",url="secondary"} 5')
    end

    it "handles a missing status payload" do
      allow(collector).to receive(:run).and_return([{ "geo_node_name" => "secondary" }])

      expect { prober.probe_db }.not_to raise_error
    end
  end
end
