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
        "status" => {
          "projects_count" => 12,
          "db_replication_lag_seconds" => 4,
          "project_repositories_count" => 21,
          "projects_verification_total_count" => 8,
          "git_fetch_event_count_weekly" => 100,
          "container_repositories_replication_enabled" => true,
          "status_message" => "Healthy"
        },
        "last_successful_status_check_timestamp" => 1_750_000_000
      }
    ]
  end

  subject(:prober) { described_class.new(metrics: metrics, collector: collector) }

  describe "#probe_db" do
    it "exports integer Geo metrics with Rails-compatible names and site labels" do
      prober.probe_db
      prober.write_to(writer)
      labels = 'name="secondary",url="secondary"'

      expect(writer.string).to include("geo_db_replication_lag_seconds{#{labels}} 4")
      expect(writer.string).to include("# TYPE geo_db_replication_lag_seconds gauge")
      expect(writer.string).to include("geo_repositories{#{labels}} 21")
      expect(writer.string).to include("geo_projects_verification_total{#{labels}} 8")
      expect(writer.string).to include("geo_last_successful_status_check_timestamp{#{labels}} 1750000000")
      expect(writer.string).not_to include("geo_projects{")
      expect(writer.string).not_to include("geo_git_fetch_event")
      expect(writer.string).not_to include("container_repositories_replication_enabled")
      expect(writer.string).not_to include("status_message")
    end

    it "handles a missing status payload" do
      allow(collector).to receive(:run).and_return([{ "geo_node_name" => "secondary" }])

      expect { prober.probe_db }.not_to raise_error
    end
  end
end
