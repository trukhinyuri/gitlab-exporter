module GitLab
  module Monitor
    module Database
      # A helper class to collect CI builds metrics.
      class CiBuildsCollector < Base # rubocop:disable ClassLength
        BUILDS_QUERY =
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
                AND ci_builds.status IN ('created', 'pending')
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
              ci_runners.is_shared,
              projects.namespace_id,
              projects.mirror,
              projects.mirror_trigger_builds,
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
              AND projects.pending_delete = 'f'
            GROUP BY
              ci_builds.runner_id,
              ci_runners.is_shared,
              ci_pipelines.pipeline_schedule_id,
              ci_builds.trigger_request_id,
              projects.mirror,
              projects.namespace_id,
              projects.mirror_trigger_builds
          SQL

        PER_RUNNER_QUERY_CE =
          <<~SQL.freeze
            SELECT
              ci_builds.runner_id,
              ci_runners.is_shared,
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
              AND projects.pending_delete = 'f'
            GROUP BY
              ci_builds.runner_id,
              ci_runners.is_shared,
              projects.namespace_id,
              ci_pipelines.pipeline_schedule_id,
              ci_builds.trigger_request_id
          SQL

        MIRROR_COLUMN_QUERY =
          <<~SQL.freeze
            SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='projects' AND column_name='mirror')
          SQL

        def run
          results = {}
          results.merge!(get_builds(BUILDS_QUERY))
          results[:stale_builds] = get_stale_builds(STALE_BUILDS_QUERY)
          query = mirror_column? ? PER_RUNNER_QUERY_EE : PER_RUNNER_QUERY_CE
          results[:per_runner] = get_per_runner(query)
          results
        end

        private

        def get_builds(query)
          results = { pending_builds: [], created_builds: [] }

          connection.exec(query).each do |row|
            row_data = { namespace: row["namespace_id"].to_s,
                         shared_runners: row["shared_runners_enabled"] == "t" ? "yes" : "no",
                         value: row["count"].to_i }

            if row["status"] == "pending"
              results[:pending_builds].push(row_data)
            elsif row["status"] == "created"
              results[:created_builds].push(row_data)
            end
          end

          results
        rescue PG::UndefinedTable, PG::UndefinedColumn
          results
        end

        def get_stale_builds(query)
          connection.exec(query)[0]["count"].to_i
        rescue PG::UndefinedTable, PG::UndefinedColumn
          0
        end

        def get_per_runner(query)
          results = []

          connection.exec(query).each do |row|
            results << transform_row_to_values(row)
          end

          results
        rescue PG::UndefinedTable, PG::UndefinedColumn
          []
        end

        def transform_row_to_values(row)
          values = { runner: row["runner_id"].to_s,
                     shared_runner: row["is_shared"] == "t" ? "yes" : "no",
                     namespace: row["namespace_id"].to_s,
                     scheduled: row["pipeline_schedule_id"] ? "yes" : "no",
                     triggered: row["trigger_request_id"] ? "yes" : "no",
                     value: row["count"].to_i }
          include_mirror_fields(values, row)
        end

        def include_mirror_fields(values, row)
          values[:mirror] = row["mirror"] == "t" ? "yes" : "no" if row["mirror"]
          values[:mirror_trigger_builds] =
            row["mirror_trigger_builds"] == "t" ? "yes" : "no" if row["mirror_trigger_builds"]
          values
        end

        def mirror_column?
          @mirror_column ||=
            begin
              connection.exec(MIRROR_COLUMN_QUERY)[0]["exists"] == "t"
            rescue PG::UndefinedColumn
              false
            end
        end
      end

      # The prober which is called when gathering metrics
      class CiBuildsProber
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics = metrics
          @collector = CiBuildsCollector.new(connection_string: opts[:connection_string])
        end

        def probe_db
          return self unless @collector.connected?

          @results = @collector.run

          ci_builds_metrics(@results[:pending_builds], "ci_pending_builds")
          ci_builds_metrics(@results[:created_builds], "ci_created_builds")
          ci_stale_builds_metrics
          metrics_per_runner

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
              other_values[key] ||= 0
              other_values[key] += metric[:value]
            else
              add_ci_created_pending_builds(metric_name, metric[:value], metric)
            end
          end

          # Add metrics for the "other" bucket.
          other_values.each { |key, value| add_ci_created_pending_builds(metric_name, value, key) }
        end

        def add_ci_created_pending_builds(metric_name, value, labels)
          add_metric_with_namespace_label(metric_name,
                                          [:namespace, :shared_runners],
                                          value,
                                          labels)
        end

        def ci_stale_builds_metrics
          @metrics.add("ci_stale_builds", @results[:stale_builds])
        end

        def metrics_per_runner
          other_values = {}

          @results[:per_runner].each do |metric|
            # If we have a low value, put the value into an "other" bucket.
            if metric[:value] < 10
              key = { runner: metric[:runner], shared_runner: metric[:shared_runner],
                      scheduled: metric[:scheduled], triggered: metric[:triggered] }
              key[:mirror] = metric[:mirror] if metric[:mirror]
              key[:mirror_trigger_builds] = metric[:mirror_trigger_builds] if metric[:mirror_trigger_builds]

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
            [:runner, :namespace, :shared_runner, :scheduled, :triggered, :mirror, :mirror_trigger_builds],
            value,
            labels
          )
        end

        def add_metric_with_namespace_label(metric_name, allowed_labels, value, labels)
          labels[:namespace] = "" unless labels[:namespace]

          selected_labels = labels.select { |k, _| allowed_labels.include?(k) }.sort.to_h
          @metrics.add(metric_name, value, selected_labels)
        end
      end
    end
  end
end
