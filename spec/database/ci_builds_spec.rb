require "spec_helper"
require "gitlab_exporter/database/ci_builds"

# rubocop:disable Metrics/LineLength
describe GitLab::Exporter::Database do
  let(:set_random_page_cost_query) { "SET random_page_cost" }
  let(:builds_query_ee) { "SELECT BUILDS EE" }
  let(:builds_query_ce) { "SELECT BUILDS CE" }
  let(:stale_builds_query) { "SELECT NOT UPDATED RUNNING" }
  let(:per_runner_query_ee) { "SELECT ALL RUNNING PER RUNNER EE" }
  let(:per_runner_query_ce) { "SELECT ALL RUNNING PER RUNNER CE" }
  let(:ee_check_query) { "SELECT COUNT(*) FROM licenses" }
  let(:repeated_commands_query_ee) { "SELECT EE REPEATED COMNANDS %d" }
  let(:repeated_commands_query_ce) { "SELECT CE REPEATED COMNANDS %d" }
  let(:unarchived_traces_query) { "SELECT UNARCHIVED TRACES %s LIST" }
  let(:connection_pool) { double("connection pool") }
  let(:connection) { double("connection") }
  let(:allowed_repeated_commands_count) { 5 }
  let(:created_builds_counting_disabled) { true }
  let(:time_now) { Time.new(2019, 4, 9, 6, 30, 0) }
  let(:unarchived_traces_query_time) { "2019-04-09 05:30:00" }
  let(:unarchived_traces_offset_minutes) { 60 }

  def stub_ee
    allow(connection).to receive(:exec).with(ee_check_query).and_return([{ "count" => 1 }])
  end

  def stub_ce
    allow(connection).to receive(:exec).with(ee_check_query).and_return([{ "count" => 0 }])
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
  def per_runner_query_row_ee(runner_id, runner_type, namespace_id, mirror, mirror_trigger_builds, pipeline_schedule_id, trigger_request_id, has_minutes, count)
    row = per_runner_query_row_ce(runner_id, runner_type, namespace_id, pipeline_schedule_id, trigger_request_id, count)
    row["mirror"] = mirror
    row["mirror_trigger_builds"] = mirror_trigger_builds
    row["has_minutes"] = has_minutes
    row
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/ParameterLists
  def per_runner_query_row_ce(runner_id, runner_type, namespace_id, pipeline_schedule_id, trigger_request_id, count)
    { "runner_id" => runner_id,
      "runner_type" => runner_type,
      "namespace_id" => namespace_id,
      "pipeline_schedule_id" => pipeline_schedule_id,
      "trigger_request_id" => trigger_request_id,
      "count" => count }
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/ParameterLists
  def repeated_commands_query_row_ee(namespace_id, shared_runners_enabled, project_id, status, has_minutes, count)
    row = repeated_commands_query_row_ce(namespace_id, shared_runners_enabled, project_id, status, count)
    row["has_minutes"] = has_minutes
    row
  end
  # rubocop:enable Metrics/ParameterLists

  def repeated_commands_query_row_ce(namespace_id, shared_runners_enabled, project_id, status, count)
    { "namespace_id" => namespace_id,
      "shared_runners_enabled" => shared_runners_enabled,
      "project_id" => project_id,
      "status" => status,
      "count" => count }
  end

  before do
    stub_const("GitLab::Exporter::Database::CiBuildsCollector::SET_RANDOM_PAGE_COST", set_random_page_cost_query)
    stub_const("GitLab::Exporter::Database::CiBuildsCollector::BUILDS_QUERY_EE", builds_query_ee)
    stub_const("GitLab::Exporter::Database::CiBuildsCollector::BUILDS_QUERY_CE", builds_query_ce)
    stub_const("GitLab::Exporter::Database::CiBuildsCollector::STALE_BUILDS_QUERY", stale_builds_query)
    stub_const("GitLab::Exporter::Database::CiBuildsCollector::PER_RUNNER_QUERY_EE", per_runner_query_ee)
    stub_const("GitLab::Exporter::Database::CiBuildsCollector::PER_RUNNER_QUERY_CE", per_runner_query_ce)
    stub_const("GitLab::Exporter::Database::CiBuildsCollector::EE_CHECK_QUERY", ee_check_query)
    stub_const("GitLab::Exporter::Database::CiBuildsCollector::REPEATED_COMMANDS_QUERY_EE", repeated_commands_query_ee)
    stub_const("GitLab::Exporter::Database::CiBuildsCollector::REPEATED_COMMANDS_QUERY_CE", repeated_commands_query_ce)
    stub_const("GitLab::Exporter::Database::CiBuildsCollector::UNARCHIVED_TRACES_QUERY", unarchived_traces_query)

    allow_any_instance_of(GitLab::Exporter::Database::CiBuildsCollector).to receive(:connection_pool).and_return(connection_pool)
    allow(connection_pool).to receive(:with).and_yield(connection)

    allow(connection).to receive(:transaction).and_yield(connection)
    allow(connection).to receive(:exec).with(set_random_page_cost_query)

    allow(Time).to receive(:now).and_return(time_now)

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
      .and_return([per_runner_query_row_ee(1, "instance_type", 1, "f", "f", 1, nil, "t", 15),
                   per_runner_query_row_ee(2, "project_type", 2, "t", "t", nil, 3, "f", 5),
                   per_runner_query_row_ee(2, "project_type", 3, "t", "t", nil, 3, "t", 5),
                   per_runner_query_row_ee(3, "project_type", 4, "t", "t", nil, 3, "f", 5)])

    allow(connection).to receive(:exec).with(per_runner_query_ce)
      .and_return([per_runner_query_row_ce(1, "instance_type", 1, 1, nil, 15),
                   per_runner_query_row_ce(2, "project_type", 2, nil, 3, 5),
                   per_runner_query_row_ce(2, "project_type", 3, nil, 3, 5),
                   per_runner_query_row_ce(3, "project_type", 4, nil, 3, 5)])

    # rubocop:disable Style/FormatString
    repeated_commands_query_ee_with_limit = repeated_commands_query_ee % [allowed_repeated_commands_count]
    repeated_commands_query_ce_with_limit = repeated_commands_query_ce % [allowed_repeated_commands_count]
    # rubocop:enable Style/FormatString

    allow(connection).to receive(:exec)
      .with(repeated_commands_query_ee_with_limit)
      .and_return([repeated_commands_query_row_ee(1, "t", 1, "pending", "t", 10),
                   repeated_commands_query_row_ee(2, "f", 2, "running", "f", 20),
                   repeated_commands_query_row_ee(1, "f", 3, "pending", "t", 30),
                   repeated_commands_query_row_ee(2, "t", 4, "running", "f", 40)])
    allow(connection).to receive(:exec)
      .with(repeated_commands_query_ce_with_limit)
      .and_return([repeated_commands_query_row_ce(1, "t", 1, "pending", 10),
                   repeated_commands_query_row_ce(2, "f", 2, "running", 20),
                   repeated_commands_query_row_ce(1, "f", 3, "pending", 30),
                   repeated_commands_query_row_ce(2, "t", 4, "running", 40)])

    unarchived_traces_query_with_time = unarchived_traces_query % [unarchived_traces_query_time] # rubocop:disable Style/FormatString

    allow(connection).to receive(:exec).with(unarchived_traces_query_with_time).and_return([{ "count" => 10 }])
  end

  describe GitLab::Exporter::Database::CiBuildsCollector do
    let(:collector) do
      described_class.new(connection_string: "host=localhost",
                          allowed_repeated_commands_count: allowed_repeated_commands_count,
                          created_builds_counting_disabled: created_builds_counting_disabled,
                          unarchived_traces_offset_minutes: unarchived_traces_offset_minutes)
    end
    let(:expected_stale_builds) { 2 }
    let(:expected_unarchived_traces) { 10 }

    shared_examples "data collector" do
      subject { collector.run }

      it "returns raw per_runner data" do
        expect(subject[:per_runner]).to include(*expected_per_runner)
      end

      it "returns raw pending_builds data" do
        expect(subject[:pending_builds]).to include(*expected_pending_builds)
      end

      context "when created_builds_counting_disabled is set to false" do
        let(:created_builds_counting_disabled) { false }

        it "returns raw created_builds data" do
          expect(subject).to have_key(:created_builds)
          expect(subject[:created_builds]).to include(*expected_created_builds)
        end
      end

      context "when created_builds_counting_disabled is set to true" do
        let(:created_builds_counting_disabled) { true }

        it "doesn't return raw created_builds data" do
          expect(subject).not_to have_key(:created_builds)
        end
      end

      it "returns raw stale_builds data" do
        expect(subject[:stale_builds]).to eq(expected_stale_builds)
      end

      it "returns raw repeated_commands data" do
        expect(subject[:repeated_commands]).to include(*expected_repeated_commands)
      end

      it "returns raw unarchived_traces data" do
        expect(subject[:unarchived_traces]).to eq(expected_unarchived_traces)
      end
    end

    context "when executed on EE" do
      let(:expected_pending_builds) do
        [{ namespace: "1", shared_runners: "yes", has_minutes: "yes", value: 30.0 },
         { namespace: "2", shared_runners: "yes", has_minutes: "yes", value: 50.0 },
         { namespace: "3", shared_runners: "yes", has_minutes: "no", value: 1.0 },
         { namespace: "4", shared_runners: "yes", has_minutes: "yes", value: 2.0 },
         { namespace: "5", shared_runners: "no", has_minutes: "no", value: 2.0 }]
      end
      let(:expected_created_builds) do
        [{ namespace: "1", shared_runners: "no", has_minutes: "no", value: 10.0 },
         { namespace: "2", shared_runners: "no", has_minutes: "no", value: 20.0 }]
      end
      let(:expected_per_runner) do
        [{ runner: "1", runner_type: "instance_type", namespace: "1", mirror: "no", mirror_trigger_builds: "no", scheduled: "yes", triggered: "no", has_minutes: "yes", value: 15.0 },
         { runner: "2", runner_type: "project_type", namespace: "2", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", has_minutes: "no", value: 5.0 },
         { runner: "2", runner_type: "project_type", namespace: "3", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", has_minutes: "yes", value: 5.0 },
         { runner: "3", runner_type: "project_type", namespace: "4", mirror: "yes", mirror_trigger_builds: "yes", scheduled: "no", triggered: "yes", has_minutes: "no", value: 5.0 }]
      end
      let(:expected_repeated_commands) do
        [{ namespace: "1", project: "1", shared_runners: "yes", status: "pending", has_minutes: "yes", value: 10.0 },
         { namespace: "2", project: "2", shared_runners: "no", status: "running", has_minutes: "no", value: 20.0 },
         { namespace: "1", project: "3", shared_runners: "no", status: "pending", has_minutes: "yes", value: 30.0 },
         { namespace: "2", project: "4", shared_runners: "yes", status: "running", has_minutes: "no", value: 40.0 }]
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
        [{ runner: "1", runner_type: "instance_type", namespace: "1", scheduled: "yes", triggered: "no", value: 15 },
         { runner: "2", runner_type: "project_type", namespace: "2", scheduled: "no", triggered: "yes", value: 5 },
         { runner: "2", runner_type: "project_type", namespace: "3", scheduled: "no", triggered: "yes", value: 5 },
         { runner: "3", runner_type: "project_type", namespace: "4", scheduled: "no", triggered: "yes", value: 5 }]
      end
      let(:expected_repeated_commands) do
        [{ namespace: "1", project: "1", shared_runners: "yes", status: "pending", value: 10 },
         { namespace: "2", project: "2", shared_runners: "no", status: "running", value: 20 },
         { namespace: "1", project: "3", shared_runners: "no", status: "pending", value: 30 },
         { namespace: "2", project: "4", shared_runners: "yes", status: "running", value: 40 }]
      end

      before do
        stub_ce
      end

      it_behaves_like "data collector"
    end
  end

  describe GitLab::Exporter::Database::CiBuildsProber do
    let(:writer) { StringIO.new }
    let(:prober) do
      opts = { connection_string: "host=localhost",
               allowed_repeated_commands_count: allowed_repeated_commands_count,
               created_builds_counting_disabled: created_builds_counting_disabled,
               unarchived_traces_offset_minutes: unarchived_traces_offset_minutes }
      described_class.new(opts,
                          metrics: GitLab::Exporter::PrometheusMetrics.new(include_timestamp: false))
    end

    before do
      allow_any_instance_of(GitLab::Exporter::Database::CiBuildsCollector).to receive(:connected?).and_return(true)
    end

    shared_examples "metrics server" do
      subject do
        prober.probe_db
        prober.write_to(writer)
        writer.string
      end

      context "when PG exceptions aren't raised" do
        context "when created_builds_counting_disabled is set to false" do
          let(:created_builds_counting_disabled) { false }

          it "responds with created builds Prometheus metrics" do
            ci_created_builds_expected_lines.each do |expected_line|
              expect(subject).to match(Regexp.new("^#{expected_line}$", Regexp::MULTILINE))
            end
          end
        end

        context "when created_builds_counting_disabled is set to true" do
          let(:created_builds_counting_disabled) { true }

          it "doesn't respond with created builds Prometheus metrics" do
            ci_created_builds_expected_lines.each do |expected_line|
              expect(subject).not_to match(Regexp.new("^#{expected_line}$", Regexp::MULTILINE))
            end
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

        it "responds with repeated commands Prometheus metrics" do
          ci_repeated_commands_builds_lines.each do |expected_line|
            expect(subject).to match(Regexp.new("^#{expected_line}$", Regexp::MULTILINE))
          end
        end

        it "responds with stale builds Prometheus metrics" do
          expect(subject).to match(/^ci_stale_builds 2.0$/m)
        end

        it "responds with unarchived traces Prometheus metrics" do
          expect(subject).to match(/^ci_unarchived_traces 10.0$/m)
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

          expect(output).to match(/^ci_stale_builds 0.0$/m)
        end
      end
    end

    context "when executed on EE" do
      let(:ci_created_builds_expected_lines) do
        ['ci_created_builds\{has_minutes="no",namespace="1",shared_runners="no"\} 10.0',
         'ci_created_builds\{has_minutes="no",namespace="2",shared_runners="no"\} 20.0']
      end
      let(:ci_pending_builds_expected_lines) do
        ['ci_pending_builds\{has_minutes="yes",namespace="1",shared_runners="yes"\} 30.0',
         'ci_pending_builds\{has_minutes="yes",namespace="2",shared_runners="yes"\} 50.0',
         'ci_pending_builds\{has_minutes="no",namespace="",shared_runners="yes"\} 1.0',
         'ci_pending_builds\{has_minutes="yes",namespace="",shared_runners="yes"\} 2.0',
         'ci_pending_builds\{has_minutes="no",namespace="",shared_runners="no"\} 2.0']
      end
      let(:ci_running_builds_expected_lines) do
        ['ci_running_builds\{has_minutes="yes",mirror="no",mirror_trigger_builds="no",namespace="1",runner="1",runner_type="instance_type",scheduled="yes",triggered="no"\} 15.0',
         'ci_running_builds\{has_minutes="no",mirror="yes",mirror_trigger_builds="yes",namespace="",runner="2",runner_type="project_type",scheduled="no",triggered="yes"\} 5.0',
         'ci_running_builds\{has_minutes="yes",mirror="yes",mirror_trigger_builds="yes",namespace="",runner="2",runner_type="project_type",scheduled="no",triggered="yes"\} 5.0',
         'ci_running_builds\{has_minutes="no",mirror="yes",mirror_trigger_builds="yes",namespace="",runner="3",runner_type="project_type",scheduled="no",triggered="yes"\} 5.0']
      end
      let(:ci_repeated_commands_builds_lines) do
        ['ci_repeated_commands_builds\{namespace="1",project="1",shared_runners="yes",status="pending",has_minutes="yes"\} 10.0',
         'ci_repeated_commands_builds\{namespace="2",project="2",shared_runners="no",status="running",has_minutes="no"\} 20.0',
         'ci_repeated_commands_builds\{namespace="1",project="3",shared_runners="no",status="pending",has_minutes="yes"\} 30.0',
         'ci_repeated_commands_builds\{namespace="2",project="4",shared_runners="yes",status="running",has_minutes="no"\} 40.0']
      end
      let(:namespace_out_of_limit) { 2 }

      before do
        stub_ee
      end

      it_behaves_like "metrics server"
    end

    context "when executed on CE" do
      let(:ci_created_builds_expected_lines) do
        ['ci_created_builds\{namespace="1",shared_runners="no"\} 10.0',
         'ci_created_builds\{namespace="2",shared_runners="no"\} 20.0']
      end
      let(:ci_pending_builds_expected_lines) do
        ['ci_pending_builds\{namespace="1",shared_runners="yes"\} 30.0',
         'ci_pending_builds\{namespace="2",shared_runners="yes"\} 50.0',
         'ci_pending_builds\{namespace="",shared_runners="yes"\} 3.0',
         'ci_pending_builds\{namespace="",shared_runners="no"\} 2.0']
      end
      let(:ci_running_builds_expected_lines) do
        ['ci_running_builds\{namespace="1",runner="1",runner_type="instance_type",scheduled="yes",triggered="no"\} 15.0',
         'ci_running_builds\{namespace="",runner="2",runner_type="project_type",scheduled="no",triggered="yes"\} 10.0',
         'ci_running_builds\{namespace="",runner="3",runner_type="project_type",scheduled="no",triggered="yes"\} 5.0']
      end
      let(:ci_repeated_commands_builds_lines) do
        ['ci_repeated_commands_builds\{namespace="1",project="1",shared_runners="yes",status="pending"\} 10.0',
         'ci_repeated_commands_builds\{namespace="2",project="2",shared_runners="no",status="running"\} 20.0',
         'ci_repeated_commands_builds\{namespace="1",project="3",shared_runners="no",status="pending"\} 30.0',
         'ci_repeated_commands_builds\{namespace="2",project="4",shared_runners="yes",status="running"\} 40.0']
      end
      let(:namespace_out_of_limit) { 0 }

      before do
        stub_ce
      end

      it_behaves_like "metrics server"
    end
  end
end
