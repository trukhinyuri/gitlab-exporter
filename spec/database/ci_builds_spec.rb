require "spec_helper"
require "gitlab_monitor/database/ci_builds"

# rubocop:disable Metrics/LineLength
describe GitLab::Monitor::Database do
  let(:builds_query) { "SELECT BUILDS" }
  let(:not_updated_running_builds_query) { "SELECT NOT UPDATED RUNNING" }
  let(:per_runner_query) { "SELECT ALL RUNNING PER RUNNER" }
  let(:connection) { double("connection") }

  before do
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::BUILDS_QUERY", builds_query)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::NOT_UPDATED_RUNNING_BUILDS_QUERY",
               not_updated_running_builds_query)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::PER_RUNNER_QUERY", per_runner_query)

    allow_any_instance_of(GitLab::Monitor::Database::CiBuildsCollector).to receive(:connection).and_return(connection)

    allow(connection).to receive(:exec).with(builds_query)
      .and_return([{ "shared_runners_enabled" => "f", "status" => "created", "path" => "foo", "count" => 10 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "path" => "foo", "count" => 30 },
                   { "shared_runners_enabled" => "f", "status" => "created", "path" => "bar", "count" => 20 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "path" => "bar", "count" => 50 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "path" => "baz", "count" => 1 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "path" => "bob", "count" => 2 }])
    allow(connection).to receive(:exec).with(not_updated_running_builds_query).and_return([{ "count" => 2 }])
    allow(connection).to receive(:exec).with(per_runner_query)
      .and_return([{ "runner_id" => 1,
                     "is_shared" => "t",
                     "mirror" => "f",
                     "pending_delete" => "f",
                     "mirror_trigger_builds" => "f",
                     "count" => 15 },
                   { "runner_id" => 2,
                     "is_shared" => "f",
                     "mirror" => "t",
                     "pending_delete" => "f",
                     "mirror_trigger_builds" => "t",
                     "count" => 5 }])
  end

  describe GitLab::Monitor::Database::CiBuildsCollector do
    let(:collector) { described_class.new(connection_string: "host=localhost") }

    it "executes the query" do
      expect(collector.run).to eq(per_runner: [
                                    { runner: "1", shared_runner: "yes", mirror: "no", pending_delete: "no", mirror_trigger_builds: "no", value: 15 },
                                    { runner: "2", shared_runner: "no", mirror: "yes", pending_delete: "no", mirror_trigger_builds: "yes", value: 5 }
                                  ],
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
      expect(writer.string).to match(/ci_pending_builds{namespace="",shared_runners="no"} 0/)
      expect(writer.string).to match(/ci_created_builds{namespace="",shared_runners="yes"} 0/)
      expect(writer.string).to match(/ci_created_builds{namespace="",shared_runners="no"} 0/)
      expect(writer.string).to match(/ci_builds_stale{status="running",when="last_hour"} 2/)
      expect(writer.string).to match(/ci_running_builds{runner="1",shared_runner="yes",mirror="no",pending_delete="no",mirror_trigger_builds="no"} 15/)
      expect(writer.string).to match(/ci_running_builds{runner="2",shared_runner="no",mirror="yes",pending_delete="no",mirror_trigger_builds="yes"} 5/)
    end
  end
end
