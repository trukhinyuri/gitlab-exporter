require "spec_helper"
require "gitlab_monitor/database/ci_builds"

# rubocop:disable Metrics/LineLength
describe GitLab::Monitor::Database do
  let(:builds_query) { "SELECT BUILDS" }
  let(:stale_builds_query) { "SELECT NOT UPDATED RUNNING" }
  let(:per_runner_query_ee) { "SELECT ALL RUNNING PER RUNNER EE" }
  let(:per_runner_query_ce) { "SELECT ALL RUNNING PER RUNNER CE" }
  let(:mirror_column_query) { "SELECT DOES MIRROR COLUMN EXISTS" }
  let(:connection) { double("connection") }

  def stub_ee
    allow(connection).to receive(:exec).with(mirror_column_query).and_return([{ "exists" => "t" }])
  end

  def stub_ce
    allow(connection).to receive(:exec).with(mirror_column_query).and_return([{ "exists" => "f" }])
  end

  def per_runner_query_row_ee(runner_id, is_shared, namespace_id, mirror, mirror_trigger_builds, pipeline_schedule_id, trigger_request_id, count)
    row = per_runner_query_row_ce(runner_id, is_shared, namespace_id, pipeline_schedule_id, trigger_request_id, count)
    row["mirror"] = mirror
    row["mirror_trigger_builds"] = mirror_trigger_builds
    row
  end

  def per_runner_query_row_ce(runner_id, is_shared, namespace_id, pipeline_schedule_id, trigger_request_id, count)
    { "runner_id" => runner_id,
      "is_shared" => is_shared,
      "namespace_id" => namespace_id,
      "pipeline_schedule_id" => pipeline_schedule_id,
      "trigger_request_id" => trigger_request_id,
      "count" => count }
  end

  before do
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::BUILDS_QUERY", builds_query)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::STALE_BUILDS_QUERY", stale_builds_query)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::PER_RUNNER_QUERY_EE", per_runner_query_ee)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::PER_RUNNER_QUERY_CE", per_runner_query_ce)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::MIRROR_COLUMN_QUERY", mirror_column_query)

    allow_any_instance_of(GitLab::Monitor::Database::CiBuildsCollector).to receive(:connection).and_return(connection)

    allow(connection).to receive(:exec).with(builds_query)
      .and_return([{ "shared_runners_enabled" => "f", "status" => "created", "namespace_id" => "1", "count" => 10 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "namespace_id" => "1", "count" => 30 },
                   { "shared_runners_enabled" => "f", "status" => "created", "namespace_id" => "2", "count" => 20 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "namespace_id" => "2", "count" => 50 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "namespace_id" => "3", "count" => 1 },
                   { "shared_runners_enabled" => "t", "status" => "pending", "namespace_id" => "4", "count" => 2 },
                   { "shared_runners_enabled" => "f", "status" => "pending", "namespace_id" => "5", "count" => 2 }])
    allow(connection).to receive(:exec).with(stale_builds_query).and_return([{ "count" => 2 }])
    allow(connection).to receive(:exec).with(per_runner_query_ee)
      .and_return([per_runner_query_row_ee(1, "t", 1, "f", "f", 1, nil, 15),
                   per_runner_query_row_ee(2, "f", 2, "t", "t", nil, 3, 5),
                   per_runner_query_row_ee(2, "f", 3, "t", "t", nil, 3, 5),
                   per_runner_query_row_ee(3, "f", 4, "t", "t", nil, 3, 5)])

    allow(connection).to receive(:exec).with(per_runner_query_ce)
      .and_return([per_runner_query_row_ce(1, "t", 1, 1, nil, 15),
                   per_runner_query_row_ce(2, "f", 2, nil, 3, 5),
                   per_runner_query_row_ce(2, "f", 3, nil, 3, 5),
                   per_runner_query_row_ce(3, "f", 4, nil, 3, 5)])
  end

  describe GitLab::Monitor::Database::CiBuildsCollector do
    let(:collector) { described_class.new(connection_string: "host=localhost") }
    let(:expected_pending_builds) {[
        { namespace: "1", shared_runners: "yes", value: 30 },
        { namespace: "2", shared_runners: "yes", value: 50 },
        { namespace: "3", shared_runners: "yes", value: 1 },
        { namespace: "4", shared_runners: "yes", value: 2 },
        { namespace: "5", shared_runners: "no", value: 2 }
    ]}
    let(:expected_created_builds) {[
        { namespace: "1", shared_runners: "no", value: 10 },
        { namespace: "2", shared_runners: "no", value: 20 }
    ]}

    let(:expected_stale_builds) { 2 }
    shared_examples "data collector" do
      it "returns raw data" do
        data = collector.run
        expect(data[:per_runner]).to include(*expected_per_runner)
        expect(data[:pending_builds]).to include(*expected_pending_builds)
        expect(data[:created_builds]).to include(*expected_created_builds)
        expect(data[:stale_builds]).to eq(expected_stale_builds)
      end
    end

    context "when executed on EE" do
      let(:expected_per_runner) {[
        { runner: "1", shared_runner: "yes", namespace: "1", mirror: "no", mirror_trigger_builds: "no", scheduled: "yes", triggered: "no", value: 15 },
        { runner: "2", shared_runner: "no", namespace: "2", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", value: 5 },
        { runner: "2", shared_runner: "no", namespace: "3", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", value: 5 },
        { runner: "3", shared_runner: "no", namespace: "4", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", value: 5 }
      ]}

      before { stub_ee }

      it_behaves_like "data collector"
    end

    context "when executed on CE" do
      let(:expected_per_runner) {[
          { runner: "1", shared_runner: "yes", namespace: "1", scheduled: "yes", triggered: "no", value: 15 },
          { runner: "2", shared_runner: "no", namespace: "2", scheduled: "no", triggered: "yes", value: 5 },
          { runner: "2", shared_runner: "no", namespace: "3", scheduled: "no", triggered: "yes", value: 5 },
          { runner: "3", shared_runner: "no", namespace: "4", scheduled: "no", triggered: "yes", value: 5 }
      ]}

      before { stub_ce }

      it_behaves_like "data collector"
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

    shared_examples "metrics server" do
      context "when PG exceptions aren't raised" do
        it "responds with Prometheus metrics" do
          prober.probe_db
          prober.write_to(writer)
          output = writer.string


          expect(output).to match(/^ci_pending_builds\{namespace="1",shared_runners="yes"\} 30$/m)
          expect(output).to match(/^ci_pending_builds\{namespace="2",shared_runners="yes"\} 50$/m)
          expect(output).to match(/^ci_pending_builds\{namespace="",shared_runners="yes"\} 3$/m)
          expect(output).to match(/^ci_pending_builds\{namespace="",shared_runners="no"\} 2$/m)
          expect(output).to match(/^ci_created_builds\{namespace="1",shared_runners="no"\} 10$/m)
          expect(output).to match(/^ci_created_builds\{namespace="2",shared_runners="no"\} 20$/m)
          expect(output).to match(/^ci_stale_builds 2$/)

          ci_running_builds_expected_lines.each do |expected_line|
            expect(output).to match(Regexp.new("^#{expected_line}$", Regexp::MULTILINE))
          end
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

    context "when executed on EE" do
      let(:ci_running_builds_expected_lines) {[
        'ci_running_builds\{mirror="no",mirror_trigger_builds="no",namespace="1",runner="1",scheduled="yes",shared_runner="yes",triggered="no"\} 15',
        'ci_running_builds\{mirror="yes",mirror_trigger_builds="yes",namespace="",runner="2",scheduled="no",shared_runner="no",triggered="yes"\} 10',
        'ci_running_builds\{mirror="yes",mirror_trigger_builds="yes",namespace="",runner="3",scheduled="no",shared_runner="no",triggered="yes"\} 5'
      ]}
      before { stub_ee }

      it_behaves_like "metrics server"

    end

    context "when executed on CE" do
      let(:ci_running_builds_expected_lines) {[
          'ci_running_builds\{namespace="1",runner="1",scheduled="yes",shared_runner="yes",triggered="no"\} 15',
          'ci_running_builds\{namespace="",runner="2",scheduled="no",shared_runner="no",triggered="yes"\} 10',
          'ci_running_builds\{namespace="",runner="3",scheduled="no",shared_runner="no",triggered="yes"\} 5'
      ]}

      before { stub_ce }

      it_behaves_like "metrics server"
    end
  end
end
