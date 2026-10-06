require "spec_helper"
require "yaml"

describe "config/gitlab-exporter.yml.example" do
  let(:config_path) { File.expand_path("../config/gitlab-exporter.yml.example", __dir__) }
  let(:config) { YAML.safe_load_file(config_path, aliases: true) }

  it "parses as valid YAML with aliases" do
    expect { config }.not_to raise_error
    expect(config).to be_a(Hash)
  end

  describe "database probes" do
    let(:database_probes) { config.dig("probes", "database") }

    it "configures geo_node_status directly under probes.database" do
      expect(database_probes).to include("geo_node_status")
      expect(database_probes["geo_node_status"]).to include(
        "class_name" => "Database::GeoNodeStatusProber",
        "methods" => ["probe_db"]
      )
    end

    it "keeps remote_mirrors and geo_node_status as sibling probes without nested leakage" do
      expect(database_probes["remote_mirrors"]).not_to have_key("geo_node_status")
      expect(database_probes.keys).to include(
        "ci_builds",
        "tuple_stats",
        "rows_count",
        "remote_mirrors",
        "geo_node_status",
        "zoekt"
      )
    end
  end
end
