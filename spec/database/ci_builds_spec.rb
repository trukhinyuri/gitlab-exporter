require "spec_helper"
require "gitlab_monitor/database/ci_builds"

# rubocop:disable Metrics/LineLength
describe GitLab::Monitor::Database do
  let(:builds_query) { "SELECT BUILDS" }
  let(:stale_builds_query) { "SELECT NOT UPDATED RUNNING" }
  let(:per_runner_query) { "SELECT ALL RUNNING PER RUNNER" }
  let(:mirror_column_query) { "SELECT EXISTS \n  (SELECT 1 FROM information_schema.columns WHERE table_name='projects' AND column_name='mirror')\n" }
  let(:connection) { double("connection") }

  before do
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::BUILDS_QUERY", builds_query)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::STALE_BUILDS_QUERY", stale_builds_query)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::PER_RUNNER_QUERY_EE", per_runner_query)

    allow_any_instance_of(GitLab::Monitor::Database::CiBuildsCollector).to receive(:connection).and_return(connection)
    allow_any_instance_of(GitLab::Monitor::Database::CiBuildsCollector).to receive(:mirror_column?).and_return(true)

    allow(connection).to receive(:exec).with(builds_query)
      .and_return([{ "shared_runners_enabled" => "f", "status" => "created", "namespace_id" => "1", "count" => 10 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "namespace_id" => "1", "count" => 30 },
                   { "shared_runners_enabled" => "f", "status" => "created", "namespace_id" => "2", "count" => 20 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "namespace_id" => "2", "count" => 50 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "namespace_id" => "3", "count" => 1 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "namespace_id" => "4", "count" => 2 },
                   { "shared_runners_enabled" => "f", "status" => "pending", "namespace_id" => "5", "count" => 2 }])
    allow(connection).to receive(:exec).with(stale_builds_query).and_return([{ "count" => 2 }])
    allow(connection).to receive(:exec).with(per_runner_query)
      .and_return([{ "runner_id" => 1,
                     "is_shared" => "t",
                     "namespace_id" => 1,
                     "mirror" => "f",
                     "mirror_trigger_builds" => "f",
                     "pipeline_schedule_id" => 1,
                     "trigger_request_id" => nil,
                     "count" => 15 },
                   { "runner_id" => 2,
                     "is_shared" => "f",
                     "namespace_id" => 2,
                     "mirror" => "t",
                     "pipeline_schedule_id" => nil,
                     "trigger_request_id" => 3,
                     "mirror_trigger_builds" => "t",
                     "count" => 5 },
                   { "runner_id" => 2,
                     "is_shared" => "f",
                     "namespace_id" => 3,
                     "mirror" => "t",
                     "pipeline_schedule_id" => nil,
                     "trigger_request_id" => 3,
                     "mirror_trigger_builds" => "t",
                     "count" => 5 },
                   { "runner_id" => 3,
                     "is_shared" => "f",
                     "namespace_id" => 4,
                     "mirror" => "t",
                     "pipeline_schedule_id" => nil,
                     "trigger_request_id" => 3,
                     "mirror_trigger_builds" => "t",
                     "count" => 5 }])
  end

  describe GitLab::Monitor::Database::CiBuildsCollector do
    let(:collector) { described_class.new(connection_string: "host=localhost") }

    it "executes the query" do
      expect(collector.run).to eq(per_runner: [
                                    { runner: "1", shared_runner: "yes", namespace: "1", mirror: "no", mirror_trigger_builds: "no", scheduled: "yes", triggered: "no", value: 15 },
                                    { runner: "2", shared_runner: "no", namespace: "2", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", value: 5 },
                                    { runner: "2", shared_runner: "no", namespace: "3", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", value: 5 },
                                    { runner: "3", shared_runner: "no", namespace: "4", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", value: 5 }
                                  ],
                                  pending_builds: [
                                    { namespace: "1", shared_runners: "yes", value: 30 },
                                    { namespace: "2", shared_runners: "yes", value: 50 },
                                    { namespace: "3", shared_runners: "yes", value: 1 },
                                    { namespace: "4", shared_runners: "yes", value: 2 },
                                    { namespace: "5", shared_runners: "no", value: 2 }
                                  ],
                                  created_builds: [
                                    { namespace: "1", shared_runners: "no", value: 10 },
                                    { namespace: "2", shared_runners: "no", value: 20 }
                                  ],
                                  stale_builds: 2)
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

    context "when no PG exceptions are raised" do
      it "responds with Prometheus metrics" do
        prober.probe_db
        prober.write_to(writer)

        output = <<~OUTPUT
          ci_pending_builds{namespace="1",shared_runners="yes"} 30
          ci_pending_builds{namespace="2",shared_runners="yes"} 50
          ci_pending_builds{namespace="",shared_runners="yes"} 3
          ci_pending_builds{namespace="",shared_runners="no"} 2
          ci_created_builds{namespace="1",shared_runners="no"} 10
          ci_created_builds{namespace="2",shared_runners="no"} 20
          ci_stale_builds 2
          ci_running_builds{runner="1",shared_runner="yes",namespace="1",mirror="no",mirror_trigger_builds="no",scheduled="yes",triggered="no"} 15
          ci_running_builds{runner="2",shared_runner="no",namespace="",mirror="yes",mirror_trigger_builds="yes",scheduled="no",triggered="yes"} 10
          ci_running_builds{runner="3",shared_runner="no",namespace="",mirror="yes",mirror_trigger_builds="yes",scheduled="no",triggered="yes"} 5
        OUTPUT

        expect(writer.string).to eq(output)
      end
    end

    context "when PG exceptions are raised" do
      before do
        allow(connection).to receive(:exec).and_raise(PG::UndefinedColumn)
      end

      it "responds with Prometheus metrics" do
        prober.probe_db
        prober.write_to(writer)

        output = <<~OUTPUT
          ci_stale_builds 0
        OUTPUT

        expect(writer.string).to eq(output)
      end
    end
  end
end
