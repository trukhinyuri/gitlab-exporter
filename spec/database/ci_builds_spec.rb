require "spec_helper"
require "gitlab_monitor/database/ci_builds"

# rubocop:disable Metrics/LineLength
describe GitLab::Monitor::Database do
  let(:set_random_page_cost_query) { "SET random_page_cost" }
  let(:builds_query_ee) { "SELECT BUILDS EE" }
  let(:builds_query_ce) { "SELECT BUILDS CE" }
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

  def builds_query_row_ee(shared_runners_enabled, status, namespace_id, has_minutes, count)
    row = builds_query_row_ce(shared_runners_enabled, status, namespace_id, count)
    row["has_minutes"] = has_minutes
    row
  end

  def builds_query_row_ce(shared_runners_enabled, status, namespace_id, count)
    { "shared_runners_enabled" => shared_runners_enabled,
      "status" => status,
      "namespace_id" => namespace_id,
      "count" => count }
  end

  # rubocop:disable Metrics/ParameterLists
  def per_runner_query_row_ee(runner_id, is_shared, namespace_id, mirror, mirror_trigger_builds, pipeline_schedule_id, trigger_request_id, has_minutes, count)
    row = per_runner_query_row_ce(runner_id, is_shared, namespace_id, pipeline_schedule_id, trigger_request_id, count)
    row["mirror"] = mirror
    row["mirror_trigger_builds"] = mirror_trigger_builds
    row["has_minutes"] = has_minutes
    row
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/ParameterLists
  def per_runner_query_row_ce(runner_id, is_shared, namespace_id, pipeline_schedule_id, trigger_request_id, count)
    { "runner_id" => runner_id,
      "is_shared" => is_shared,
      "namespace_id" => namespace_id,
      "pipeline_schedule_id" => pipeline_schedule_id,
      "trigger_request_id" => trigger_request_id,
      "count" => count }
  end
  # rubocop:enable Metrics/ParameterLists

  before do
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::SET_RANDOM_PAGE_COST", set_random_page_cost_query)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::BUILDS_QUERY_EE", builds_query_ee)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::BUILDS_QUERY_CE", builds_query_ce)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::STALE_BUILDS_QUERY", stale_builds_query)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::PER_RUNNER_QUERY_EE", per_runner_query_ee)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::PER_RUNNER_QUERY_CE", per_runner_query_ce)
    stub_const("GitLab::Monitor::Database::CiBuildsCollector::MIRROR_COLUMN_QUERY", mirror_column_query)

    allow_any_instance_of(GitLab::Monitor::Database::CiBuildsCollector).to receive(:connection).and_return(connection)

    allow(connection).to receive(:transaction).and_yield(connection)
    allow(connection).to receive(:exec).with(set_random_page_cost_query)

    allow(connection).to receive(:exec).with(builds_query_ee)
      .and_return([builds_query_row_ee("f", "created", "1", "f", 10),
                   builds_query_row_ee("t", "pending", "1", "t", 30),
                   builds_query_row_ee("f", "created", "2", "f", 20),
                   builds_query_row_ee("t", "pending", "2", "t", 50),
                   builds_query_row_ee("t", "pending", "3", "f", 1),
                   builds_query_row_ee("t", "pending", "4", "t", 2),
                   builds_query_row_ee("f", "pending", "5", "f", 2)])
    allow(connection).to receive(:exec).with(builds_query_ce)
      .and_return([builds_query_row_ce("f", "created", "1", 10),
                   builds_query_row_ce("t", "pending", "1", 30),
                   builds_query_row_ce("f", "created", "2", 20),
                   builds_query_row_ce("t", "pending", "2", 50),
                   builds_query_row_ce("t", "pending", "3", 1),
                   builds_query_row_ce("t", "pending", "4", 2),
                   builds_query_row_ce("f", "pending", "5", 2)])

    allow(connection).to receive(:exec).with(stale_builds_query).and_return([{ "count" => 2 }])

    allow(connection).to receive(:exec).with(per_runner_query_ee)
      .and_return([per_runner_query_row_ee(1, "t", 1, "f", "f", 1, nil, "t", 15),
                   per_runner_query_row_ee(2, "f", 2, "t", "t", nil, 3, "f", 5),
                   per_runner_query_row_ee(2, "f", 3, "t", "t", nil, 3, "t", 5),
                   per_runner_query_row_ee(3, "f", 4, "t", "t", nil, 3, "f", 5)])

    allow(connection).to receive(:exec).with(per_runner_query_ce)
      .and_return([per_runner_query_row_ce(1, "t", 1, 1, nil, 15),
                   per_runner_query_row_ce(2, "f", 2, nil, 3, 5),
                   per_runner_query_row_ce(2, "f", 3, nil, 3, 5),
                   per_runner_query_row_ce(3, "f", 4, nil, 3, 5)])
  end

  describe GitLab::Monitor::Database::CiBuildsCollector do
    let(:collector) { described_class.new(connection_string: "host=localhost") }
    let(:expected_stale_builds) { 2 }

    shared_examples "data collector" do
      subject { collector.run }

      it "returns raw per_runner data" do
        expect(subject[:per_runner]).to include(*expected_per_runner)
      end

      it "returns raw pending_builds data" do
        expect(subject[:pending_builds]).to include(*expected_pending_builds)
      end

      it "returns raw created_builds data" do
        expect(subject[:created_builds]).to include(*expected_created_builds)
      end

      it "returns raw stale_builds data" do
        expect(subject[:stale_builds]).to eq(expected_stale_builds)
      end
    end

    context "when executed on EE" do
      let(:expected_pending_builds) do
        [{ namespace: "1", shared_runners: "yes", has_minutes: "yes", value: 30 },
         { namespace: "2", shared_runners: "yes", has_minutes: "yes", value: 50 },
         { namespace: "3", shared_runners: "yes", has_minutes: "no", value: 1 },
         { namespace: "4", shared_runners: "yes", has_minutes: "yes", value: 2 },
         { namespace: "5", shared_runners: "no", has_minutes: "no", value: 2 }]
      end
      let(:expected_created_builds) do
        [{ namespace: "1", shared_runners: "no", has_minutes: "no", value: 10 },
         { namespace: "2", shared_runners: "no", has_minutes: "no", value: 20 }]
      end
      let(:expected_per_runner) do
        [{ runner: "1", shared_runner: "yes", namespace: "1", mirror: "no", mirror_trigger_builds: "no", scheduled: "yes", triggered: "no", has_minutes: "yes", value: 15 },
         { runner: "2", shared_runner: "no", namespace: "2", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", has_minutes: "no", value: 5 },
         { runner: "2", shared_runner: "no", namespace: "3", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", has_minutes: "yes", value: 5 },
         { runner: "3", shared_runner: "no", namespace: "4", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", has_minutes: "no", value: 5 }]
      end

      before do
        stub_ee
      end

      it_behaves_like "data collector"
    end

    context "when executed on CE" do
      let(:expected_pending_builds) do
        [{ namespace: "1", shared_runners: "yes", value: 30 },
         { namespace: "2", shared_runners: "yes", value: 50 },
         { namespace: "3", shared_runners: "yes", value: 1 },
         { namespace: "4", shared_runners: "yes", value: 2 },
         { namespace: "5", shared_runners: "no", value: 2 }]
      end
      let(:expected_created_builds) do
        [{ namespace: "1", shared_runners: "no", value: 10 },
         { namespace: "2", shared_runners: "no", value: 20 }]
      end
      let(:expected_per_runner) do
        [{ runner: "1", shared_runner: "yes", namespace: "1", scheduled: "yes", triggered: "no", value: 15 },
         { runner: "2", shared_runner: "no", namespace: "2", scheduled: "no", triggered: "yes", value: 5 },
         { runner: "2", shared_runner: "no", namespace: "3", scheduled: "no", triggered: "yes", value: 5 },
         { runner: "3", shared_runner: "no", namespace: "4", scheduled: "no", triggered: "yes", value: 5 }]
      end

      before do
        stub_ce
      end

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
      subject do
        prober.probe_db
        prober.write_to(writer)
        writer.string
      end

      context "when PG exceptions aren't raised" do
        it "responds with created builds Prometheus metrics" do
          ci_created_builds_expected_lines.each do |expected_line|
            expect(subject).to match(Regexp.new("^#{expected_line}$", Regexp::MULTILINE))
          end
        end

        it "responds with pending builds Prometheus metrics" do
          ci_pending_builds_expected_lines.each do |expected_line|
            expect(subject).to match(Regexp.new("^#{expected_line}$", Regexp::MULTILINE))
          end
        end

        it "responds with running builds Prometheus metrics" do
          ci_running_builds_expected_lines.each do |expected_line|
            expect(subject).to match(Regexp.new("^#{expected_line}$", Regexp::MULTILINE))
          end
        end

        it "responds with stale builds Prometheus metrics" do
          expect(subject).to match(/^ci_stale_builds 2$/m)
        end
      end

      context "when PG exceptions are raised" do
        before do
          allow(connection).to receive(:exec).and_raise(PG::UndefinedColumn)
        end

        it "responds with Prometheus metrics" do
          prober.probe_db
          prober.write_to(writer)
          output = writer.string

          expect(output).to match(/^ci_stale_builds 0$/m)
        end
      end
    end

    context "when executed on EE" do
      let(:ci_created_builds_expected_lines) do
        ['ci_created_builds\{has_minutes="no",namespace="1",shared_runners="no"\} 10',
         'ci_created_builds\{has_minutes="no",namespace="2",shared_runners="no"\} 20']
      end
      let(:ci_pending_builds_expected_lines) do
        ['ci_pending_builds\{has_minutes="yes",namespace="1",shared_runners="yes"\} 30',
         'ci_pending_builds\{has_minutes="yes",namespace="2",shared_runners="yes"\} 50',
         'ci_pending_builds\{has_minutes="no",namespace="",shared_runners="yes"\} 1',
         'ci_pending_builds\{has_minutes="yes",namespace="",shared_runners="yes"\} 2',
         'ci_pending_builds\{has_minutes="no",namespace="",shared_runners="no"\} 2']
      end
      let(:ci_running_builds_expected_lines) do
        ['ci_running_builds\{has_minutes="yes",mirror="no",mirror_trigger_builds="no",namespace="1",runner="1",scheduled="yes",shared_runner="yes",triggered="no"\} 15',
         'ci_running_builds\{has_minutes="no",mirror="yes",mirror_trigger_builds="yes",namespace="",runner="2",scheduled="no",shared_runner="no",triggered="yes"\} 5',
         'ci_running_builds\{has_minutes="yes",mirror="yes",mirror_trigger_builds="yes",namespace="",runner="2",scheduled="no",shared_runner="no",triggered="yes"\} 5',
         'ci_running_builds\{has_minutes="no",mirror="yes",mirror_trigger_builds="yes",namespace="",runner="3",scheduled="no",shared_runner="no",triggered="yes"\} 5']
      end
      let(:namespace_out_of_limit) { 2 }

      before do
        stub_ee
      end

      it_behaves_like "metrics server"
    end

    context "when executed on CE" do
      let(:ci_created_builds_expected_lines) do
        ['ci_created_builds\{namespace="1",shared_runners="no"\} 10',
         'ci_created_builds\{namespace="2",shared_runners="no"\} 20']
      end
      let(:ci_pending_builds_expected_lines) do
        ['ci_pending_builds\{namespace="1",shared_runners="yes"\} 30',
         'ci_pending_builds\{namespace="2",shared_runners="yes"\} 50',
         'ci_pending_builds\{namespace="",shared_runners="yes"\} 3',
         'ci_pending_builds\{namespace="",shared_runners="no"\} 2']
      end
      let(:ci_running_builds_expected_lines) do
        ['ci_running_builds\{namespace="1",runner="1",scheduled="yes",shared_runner="yes",triggered="no"\} 15',
         'ci_running_builds\{namespace="",runner="2",scheduled="no",shared_runner="no",triggered="yes"\} 10',
         'ci_running_builds\{namespace="",runner="3",scheduled="no",shared_runner="no",triggered="yes"\} 5']
      end
      let(:namespace_out_of_limit) { 0 }

      before do
        stub_ce
      end

      it_behaves_like "metrics server"
    end
  end
end
