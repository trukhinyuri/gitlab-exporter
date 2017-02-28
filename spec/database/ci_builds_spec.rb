require "spec_helper"
require "gitlab_monitor/database/ci_builds"

describe GitLab::Monitor::Database do
  let(:builds_query) { "SELECT BUILDS" }
  let(:not_updated_running_builds_query) { "SELECT NOT UPDATED RUNNING" }
  let(:per_runner_query) { "SELECT ALL RUNNING PER RUNNER %s" }
  let(:mirrors_per_runner_query) { "SELECT MIRRORS RUNNING PER RUNNER %s" }
  let(:connection) { double("connection") }

  before do
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::BUILDS_QUERY", builds_query)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::NOT_UPDATED_RUNNING_BUILDS_QUERY",
               not_updated_running_builds_query)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::RUNNING_PER_SHARED_RUNNER_QUERY", per_runner_query)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::RUNNING_FOR_MIRRORS_PER_SHARED_RUNNER_QUERY",
               mirrors_per_runner_query)

    allow_any_instance_of(GitLab::Monitor::Database::CiBuildsCollector).to receive(:connection).and_return(connection)
    allow_any_instance_of(GitLab::Monitor::Database::CiBuildsCollector).to receive(:shared_runners_ids)
      .and_return([1, 2])

    allow(connection).to receive(:exec).with(builds_query)
      .and_return([{ "shared_runners_enabled" => "f", "status" => "created", "path" => "foo", "count" => 10 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "path" => "foo", "count" => 30 },
                   { "shared_runners_enabled" => "f", "status" => "created", "path" => "bar", "count" => 20 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "path" => "bar", "count" => 50 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "path" => "baz", "count" => 1 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "path" => "bob", "count" => 2 }])
    allow(connection).to receive(:exec).with(not_updated_running_builds_query).and_return([{ "count" => 2 }])
    allow(connection).to receive(:exec).with(per_runner_query % "1, 2")
      .and_return([{ "runner_id" => 2, "count" => 15 }])
    allow(connection).to receive(:exec).with(mirrors_per_runner_query % "1, 2")
      .and_return([{ "runner_id" => 2, "count" => 10 }])
  end

  describe GitLab::Monitor::Database::CiBuildsCollector do
    let(:collector) { described_class.new(connection_string: "host=localhost") }

    it "executes the query" do
      expect(collector.run).to eq(per_runner: { 1 => 0, 2 => 15 },
                                  per_runner_mirrors: { 1 => 0, 2 => 10 },
                                  pending_builds: [
                                    { namespace: "foo", shared_runners: "yes", value: 30 },
                                    { namespace: "bar", shared_runners: "yes", value: 50 },
                                    { namespace: "baz", shared_runners: "yes", value: 1 },
                                    { namespace: "bob", shared_runners: "yes", value: 2 }
                                  ],
                                  created_builds: [
                                    { namespace: "foo", shared_runners: "no", value: 10 },
                                    { namespace: "bar", shared_runners: "no", value: 20 }
                                  ],
                                  not_updated_last_hour: 2)
    end
  end

  describe GitLab::Monitor::Database::CiBuildsProber do
    let(:writer) { StringIO.new }
    let(:prober) do
      described_class.new({ connection_string: "host=localhost" },
                          metrics: GitLab::Monitor::PrometheusMetrics.new(include_timestamp: false))
    end

    before do
      allow_any_instance_of(GitLab::Monitor::Database::CiBuildsCollector).to receive(:connected?).and_return(true)
    end

    it "responds with Prometheus metrics" do
      prober.probe_db
      prober.write_to(writer)

      expect(writer.string).to match(/ci_created_builds{namespace="foo",shared_runners="no"} 10/)
      expect(writer.string).to match(/ci_created_builds{namespace="bar",shared_runners="no"} 20/)
      expect(writer.string).to match(/ci_pending_builds{namespace="foo",shared_runners="yes"} 30/)
      expect(writer.string).to match(/ci_pending_builds{namespace="bar",shared_runners="yes"} 50/)
      expect(writer.string).to match(/ci_pending_builds{namespace="",shared_runners="yes"} 3/)
      expect(writer.string).to match(/ci_builds_stale{status="running",when="last_hour"} 2/)
      expect(writer.string).to match(/ci_builds_per_runner{status="running",runner="1",mirrors="0"} 0/)
      expect(writer.string).to match(/ci_builds_per_runner{status="running",runner="2",mirrors="0"} 5/)
      expect(writer.string).to match(/ci_builds_per_runner{status="running",runner="1",mirrors="1"} 0/)
      expect(writer.string).to match(/ci_builds_per_runner{status="running",runner="2",mirrors="1"} 10/)
    end
  end
end
