module GitLab
  module Exporter
    module Database
      # A helper class to collect CI builds metrics.
      class CiBuildsCollector < Base # rubocop:disable Metrics/ClassLength
        SET_RANDOM_PAGE_COST = "SET LOCAL random_page_cost TO 1".freeze

        BUILDS_QUERY_EE =
          <<~SQL.freeze
            SELECT
              projects.namespace_id,
              ci_builds.status,
              projects.shared_runners_enabled,
              (COALESCE(namespaces.shared_runners_minutes_limit, application_settings.shared_runners_minutes, 0) = 0 OR
                 COALESCE(namespace_statistics.shared_runners_seconds, 0) < COALESCE(namespaces.shared_runners_minutes_limit, application_settings.shared_runners_minutes, 0) * 60) as has_minutes,
              COUNT(*) AS count
            FROM ci_builds
            JOIN projects
              ON projects.id = ci_builds.project_id
            JOIN namespaces
              ON namespaces.id = projects.namespace_id
            LEFT JOIN namespace_statistics
              ON namespace_statistics.namespace_id = namespaces.id
            JOIN application_settings
              ON application_settings.id = 1
            WHERE ci_builds.type = 'Ci::Build'
              AND ci_builds.status = '%s'
              -- The created_at filter has been introduced for performance reasons only
              AND ci_builds.created_at > NOW() - INTERVAL '7 days'
              AND projects.pending_delete = 'f'
            GROUP BY
              projects.namespace_id,
              ci_builds.status,
              projects.shared_runners_enabled,
              namespaces.shared_runners_minutes_limit,
              namespace_statistics.shared_runners_seconds,
              application_settings.shared_runners_minutes
          SQL

        BUILDS_QUERY_CE =
          <<~SQL.freeze
            SELECT
              projects.namespace_id,
              ci_builds.status,
              projects.shared_runners_enabled,
              COUNT(*) AS count
            FROM ci_builds
            JOIN projects
              ON projects.id = ci_builds.project_id
            WHERE ci_builds.type = 'Ci::Build'
              AND ci_builds.status = '%s'
              -- The created_at filter has been introduced for performance reasons only
              AND ci_builds.created_at > NOW() - INTERVAL '7 days'
              AND projects.pending_delete = 'f'
            GROUP BY
              projects.namespace_id,
              ci_builds.status,
              projects.shared_runners_enabled
          SQL

        STALE_BUILDS_QUERY =
          <<~SQL.freeze
            SELECT
              COUNT(*) AS count
            FROM ci_builds
            JOIN projects
              ON projects.id = ci_builds.project_id
            WHERE ci_builds.type = 'Ci::Build'
              AND ci_builds.status = 'running'
              AND ci_builds.updated_at < NOW() - INTERVAL '1 hour'
              AND projects.pending_delete = 'f'
          SQL

        PER_RUNNER_QUERY_EE =
          <<~SQL.freeze
            SELECT
              ci_builds.runner_id,
              ci_runners.runner_type,
              projects.namespace_id,
              projects.mirror,
              projects.mirror_trigger_builds,
              ci_pipelines.pipeline_schedule_id,
              ci_builds.trigger_request_id,
              (COALESCE(namespaces.shared_runners_minutes_limit, application_settings.shared_runners_minutes, 0) = 0 OR
                 COALESCE(namespace_statistics.shared_runners_seconds, 0) < COALESCE(namespaces.shared_runners_minutes_limit, application_settings.shared_runners_minutes, 0) * 60) as has_minutes,
              COUNT(*) AS count
            FROM ci_builds
            JOIN ci_runners
              ON ci_runners.id = ci_builds.runner_id
            JOIN projects
              ON projects.id = ci_builds.project_id
            JOIN ci_pipelines
              ON ci_pipelines.id = ci_builds.commit_id
            JOIN namespaces
              ON namespaces.id = projects.namespace_id
            LEFT JOIN namespace_statistics
              ON namespace_statistics.namespace_id = namespaces.id
            JOIN application_settings
              ON application_settings.id = 1
            WHERE ci_builds.type = 'Ci::Build'
              AND ci_builds.status = 'running'
              -- The created_at filter has been introduced for performance reasons only
              AND ci_builds.created_at > NOW() - INTERVAL '7 days'
              AND projects.pending_delete = 'f'
            GROUP BY
              ci_builds.runner_id,
              ci_runners.runner_type,
              projects.namespace_id,
              projects.mirror,
              projects.mirror_trigger_builds,
              ci_pipelines.pipeline_schedule_id,
              ci_builds.trigger_request_id,
              namespaces.shared_runners_minutes_limit,
              namespace_statistics.shared_runners_seconds,
              application_settings.shared_runners_minutes
          SQL

        PER_RUNNER_QUERY_CE =
          <<~SQL.freeze
            SELECT
              ci_builds.runner_id,
              ci_runners.runner_type,
              projects.namespace_id,
              ci_pipelines.pipeline_schedule_id,
              ci_builds.trigger_request_id,
              COUNT(*) AS count
            FROM ci_builds
            JOIN ci_runners
              ON ci_runners.id = ci_builds.runner_id
            JOIN projects
              ON projects.id = ci_builds.project_id
            JOIN ci_pipelines
              ON ci_pipelines.id = ci_builds.commit_id
            WHERE ci_builds.type = 'Ci::Build'
              AND ci_builds.status = 'running'
              -- The created_at filter has been introduced for performance reasons only
              AND ci_builds.created_at > NOW() - INTERVAL '7 days'
              AND projects.pending_delete = 'f'
            GROUP BY
              ci_builds.runner_id,
              ci_runners.runner_type,
              projects.namespace_id,
              ci_pipelines.pipeline_schedule_id,
              ci_builds.trigger_request_id
          SQL

        MIRROR_COLUMN_QUERY =
          <<~SQL.freeze
            SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='projects' AND column_name='mirror')
          SQL

        REPEATED_COMMANDS_QUERY_EE =
          <<~SQL.freeze
            SELECT
              subquery.namespace_id,
              subquery.shared_runners_enabled,
              subquery.project_id,
              subquery.status,
              subquery.has_minutes,
              MAX(subquery.count) as count
            FROM (
              SELECT
                projects.namespace_id,
                projects.shared_runners_enabled,
                ci_builds.project_id,
                ci_builds.commit_id,
                ci_builds.status,
                (COALESCE(namespaces.shared_runners_minutes_limit, application_settings.shared_runners_minutes, 0) = 0 OR
                   COALESCE(namespace_statistics.shared_runners_seconds, 0) < COALESCE(namespaces.shared_runners_minutes_limit, application_settings.shared_runners_minutes, 0) * 60) as has_minutes,
                COUNT(*) AS count
              FROM ci_builds
              JOIN projects
                ON projects.id = ci_builds.project_id
              JOIN namespaces
                ON namespaces.id = projects.namespace_id
              LEFT JOIN namespace_statistics
                ON namespace_statistics.namespace_id = namespaces.id
              JOIN application_settings
                ON application_settings.id = 1
              WHERE ci_builds.type = 'Ci::Build'
                AND ci_builds.status IN ('running', 'pending')
                -- The created_at filter has been introduced for performance reasons only
                AND ci_builds.created_at > NOW() - INTERVAL '7 days'
              GROUP BY
                projects.namespace_id,
                projects.shared_runners_enabled,
                ci_builds.project_id,
                ci_builds.commit_id,
                ci_builds.status,
                ci_builds.commands,
                namespaces.shared_runners_minutes_limit,
                namespace_statistics.shared_runners_seconds,
                application_settings.shared_runners_minutes
              HAVING COUNT(*) > %d
            ) AS subquery
            GROUP BY
              subquery.namespace_id,
              subquery.shared_runners_enabled,
              subquery.project_id,
              subquery.commit_id,
              subquery.status,
              subquery.has_minutes
          SQL

        REPEATED_COMMANDS_QUERY_CE =
          <<~SQL.freeze
            SELECT
              subquery.namespace_id,
              subquery.shared_runners_enabled,
              subquery.project_id,
              subquery.status,
              MAX(subquery.count) as count
            FROM (
              SELECT
                projects.namespace_id,
                projects.shared_runners_enabled,
                ci_builds.project_id,
                ci_builds.commit_id,
                ci_builds.status,
                COUNT(*) AS count
              FROM ci_builds
              JOIN projects
                ON projects.id = ci_builds.project_id
              JOIN namespaces
                ON namespaces.id = projects.namespace_id
              WHERE ci_builds.type = 'Ci::Build'
                AND ci_builds.status IN ('running', 'pending')
              -- The created_at filter has been introduced for performance reasons only
              AND ci_builds.created_at > NOW() - INTERVAL '7 days'
              GROUP BY
                projects.namespace_id,
                projects.shared_runners_enabled,
                ci_builds.project_id,
                ci_builds.commit_id,
                ci_builds.status,
                ci_builds.commands
              HAVING COUNT(*) > %d
            ) AS subquery
            GROUP BY
              subquery.namespace_id,
              subquery.shared_runners_enabled,
              subquery.project_id,
              subquery.commit_id,
              subquery.status
          SQL

        UNARCHIVED_TRACES_QUERY =
          <<~SQL.freeze
            SELECT
              COUNT(*) as count
            FROM ci_builds
            JOIN ci_build_trace_chunks
              ON ci_build_trace_chunks.build_id = ci_builds.id
            LEFT JOIN ci_job_artifacts
              ON ci_job_artifacts.job_id = ci_builds.id
              AND ci_job_artifacts.file_type = 3
            WHERE ci_builds.type = 'Ci::Build'
              AND ci_builds.status IN ('success', 'failed', 'canceled')
              AND ci_builds.finished_at < '%s'
              AND ci_job_artifacts.job_id IS NULL
          SQL

        STATUS_CREATED = "created".freeze
        STATUS_PENDING = "pending".freeze

        DEFAULT_UNARCHIVED_TRACES_OFFSET_MINUTES = 1440

        def initialize(opts)
          super(opts)

          @allowed_repeated_commands_count = opts[:allowed_repeated_commands_count]
          @created_builds_counting_disabled = opts[:created_builds_counting_disabled]
          @unarchived_traces_offset_minutes = opts[:unarchived_traces_offset_minutes]
        end

        def run
          results = {}
          results[:created_builds] = builds(STATUS_CREATED) unless @created_builds_counting_disabled
          results[:pending_builds] = builds(STATUS_PENDING)
          results[:stale_builds] = stale_builds
          results[:per_runner] = per_runner_builds
          results[:repeated_commands] = repeated_commands
          results[:unarchived_traces] = unarchived_traces
          results
        end

        private

        def builds(status)
          results = []

          query = mirror_column? ? BUILDS_QUERY_EE : BUILDS_QUERY_CE
          query = query % [status] # rubocop:disable Style/FormatString
          exec_query_with_custom_random_page_cost(query).each do |row|
            results << transform_builds_row_to_values(row)
          end

          results
        rescue PG::UndefinedTable, PG::UndefinedColumn
          results
        end

        def transform_builds_row_to_values(row)
          values = { namespace: row["namespace_id"].to_s,
                     shared_runners: row["shared_runners_enabled"] == "t" ? "yes" : "no",
                     value: row["count"].to_i }
          include_ee_fields(values, row)
        end

        def stale_builds
          with_connection_pool do |conn|
            conn.exec(STALE_BUILDS_QUERY)[0]["count"].to_i
          end
        rescue PG::UndefinedTable, PG::UndefinedColumn
          0
        end

        def per_runner_builds
          results = []

          query = mirror_column? ? PER_RUNNER_QUERY_EE : PER_RUNNER_QUERY_CE
          exec_query_with_custom_random_page_cost(query).each do |row|
            results << transform_per_runners_builds_row_to_values(row)
          end

          results
        rescue PG::UndefinedTable, PG::UndefinedColumn
          []
        end

        def transform_per_runners_builds_row_to_values(row)
          values = { runner: row["runner_id"].to_s,
                     runner_type: row["runner_type"],
                     namespace: row["namespace_id"].to_s,
                     scheduled: row["pipeline_schedule_id"] ? "yes" : "no",
                     triggered: row["trigger_request_id"] ? "yes" : "no",
                     value: row["count"].to_i }
          include_ee_fields(values, row)
        end

        def repeated_commands
          results = []

          query = mirror_column? ? REPEATED_COMMANDS_QUERY_EE : REPEATED_COMMANDS_QUERY_CE
          query = query % [allowed_repeated_commands_count] # rubocop:disable Style/FormatString
          exec_query_with_custom_random_page_cost(query).each do |row|
            results << transform_repeated_commands_row_to_values(row)
          end

          results
        rescue PG::UndefinedTable, PG::UndefinedColumn
          []
        end

        def allowed_repeated_commands_count
          @allowed_repeated_commands_count ||= 2
        end

        def transform_repeated_commands_row_to_values(row)
          values = { namespace: row["namespace_id"].to_s,
                     project: row["project_id"].to_s,
                     shared_runners: row["shared_runners_enabled"] == "t" ? "yes" : "no",
                     status: row["status"].to_s,
                     value: row["count"].to_i }

          include_has_minutes_field(values, row)
        end

        def unarchived_traces
          time = Time.now - (unarchived_traces_offset_minutes * 60)
          query = UNARCHIVED_TRACES_QUERY % [time.strftime("%F %T")] # rubocop:disable Style/FormatString

          with_connection_pool do |conn|
            conn.exec(query)[0]["count"].to_i
          end
        rescue PG::UndefinedTable, PG::UndefinedColumn
          0
        end

        def unarchived_traces_offset_minutes
          @unarchived_traces_offset_minutes ||= DEFAULT_UNARCHIVED_TRACES_OFFSET_MINUTES
        end

        def include_ee_fields(values, row)
          values.merge!(include_bool_if_row_defined(row, :mirror))
          values.merge!(include_bool_if_row_defined(row, :mirror_trigger_builds))
          include_has_minutes_field(values, row)
        end

        def include_has_minutes_field(values, row)
          values.merge!(include_bool_if_row_defined(row, :has_minutes))
          values
        end

        def include_bool_if_row_defined(row, field)
          return {} unless row[field.to_s]
          { field => row[field.to_s] == "t" ? "yes" : "no" }
        end

        def exec_query_with_custom_random_page_cost(query)
          with_connection_pool do |conn|
            conn.transaction do |trans|
              trans.exec(SET_RANDOM_PAGE_COST)
              trans.exec(query)
            end
          end
        end

        def mirror_column?
          @mirror_column ||=
            begin
              with_connection_pool do |conn|
                conn.exec(MIRROR_COLUMN_QUERY)[0]["exists"] == "t"
              end
            rescue PG::UndefinedColumn
              false
            end
        end
      end

      # The prober which is called when gathering metrics
      class CiBuildsProber
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics = metrics

          collector_opts = { connection_string: opts[:connection_string],
                             allowed_repeated_commands_count: opts[:allowed_repeated_commands_count],
                             created_builds_counting_disabled: opts[:created_builds_counting_disabled],
                             unarchived_traces_offset_minutes: opts[:unarchived_traces_offset_minutes] }
          @collector = CiBuildsCollector.new(collector_opts)
        end

        def probe_db
          @results = @collector.run

          ci_builds_metrics(@results[:created_builds], "ci_created_builds") if @results[:created_builds]
          ci_builds_metrics(@results[:pending_builds], "ci_pending_builds")
          ci_stale_builds_metrics
          metrics_per_runner
          repeated_commands_metrics
          unarchived_traces_metrics

          self
        rescue PG::ConnectionBad
          self
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end

        private

        def ci_builds_metrics(results_list, metric_name)
          other_values = {}

          results_list.each do |metric|
            # If we have a low value, put the value into an "other" bucket.
            if metric[:value] < 10
              key = { shared_runners: metric[:shared_runners] }
              key[:has_minutes] = metric[:has_minutes] if metric[:has_minutes]

              other_values[key] ||= 0
              other_values[key] += metric[:value]
            else
              add_ci_created_pending_builds(metric_name, metric[:value].to_f, metric)
            end
          end

          # Add metrics for the "other" bucket.
          other_values.each { |key, value| add_ci_created_pending_builds(metric_name, value, key) }
        end

        def add_ci_created_pending_builds(metric_name, value, labels)
          add_metric_with_namespace_label(metric_name,
                                          [:namespace, :shared_runners, :has_minutes],
                                          value,
                                          labels)
        end

        def ci_stale_builds_metrics
          @metrics.add("ci_stale_builds", @results[:stale_builds].to_f)
        end

        def metrics_per_runner
          other_values = {}

          @results[:per_runner].each do |metric|
            # If we have a low value, put the value into an "other" bucket.
            if metric[:value] < 10
              key = { runner: metric[:runner], runner_type: metric[:runner_type],
                      scheduled: metric[:scheduled], triggered: metric[:triggered] }
              key[:mirror] = metric[:mirror] if metric[:mirror]
              key[:mirror_trigger_builds] = metric[:mirror_trigger_builds] if metric[:mirror_trigger_builds]
              key[:has_minutes] = metric[:has_minutes] if metric[:has_minutes]

              other_values[key] ||= 0
              other_values[key] += metric[:value]
            else
              add_ci_running_builds(metric[:value], metric)
            end
          end

          # Add metrics for the "other" bucket.
          other_values.each { |key, value| add_ci_running_builds(value, key) }
        end

        def add_ci_running_builds(value, labels)
          add_metric_with_namespace_label(
            "ci_running_builds",
            [:runner, :namespace, :runner_type, :scheduled,
             :triggered, :mirror, :mirror_trigger_builds, :has_minutes],
            value,
            labels
          )
        end

        def add_metric_with_namespace_label(metric_name, allowed_labels, value, labels)
          labels[:namespace] = "" unless labels[:namespace]

          selected_labels = labels.select { |k, _| allowed_labels.include?(k) }.sort.to_h
          @metrics.add(metric_name, value.to_f, selected_labels)
        end

        def repeated_commands_metrics
          @results[:repeated_commands].each do |metric|
            value = metric.delete(:value)

            @metrics.add("ci_repeated_commands_builds", value.to_f, metric)
          end
        end

        def unarchived_traces_metrics
          @metrics.add("ci_unarchived_traces", @results[:unarchived_traces].to_f)
        end
      end
    end
  end
end
