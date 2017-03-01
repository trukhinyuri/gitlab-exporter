module GitLab
  module Monitor
    module Database
      # A helper class to collect blocked queries
      class CiBuildsCollector < Base
        BUILDS_QUERY =
          "SELECT " \
          "  namespaces.path, " \
          "  ci_builds.status, " \
          "  projects.shared_runners_enabled, " \
          "  COUNT(*) AS count " \
          "  FROM ci_builds " \
          "  JOIN projects " \
          "    ON projects.id = ci_builds.gl_project_id " \
          "  JOIN namespaces " \
          "    ON namespaces.id = projects.namespace_id " \
          "  WHERE ci_builds.type = 'Ci::Build' " \
          "    AND ci_builds.status IN ('created', 'pending') " \
          "  GROUP BY " \
          "    namespaces.path, " \
          "    ci_builds.status, " \
          "    projects.shared_runners_enabled".freeze

        NOT_UPDATED_RUNNING_BUILDS_QUERY =
          "SELECT " \
          "  COUNT(*) AS count " \
          "  FROM ci_builds " \
          "  WHERE ci_builds.type = 'Ci::Build' " \
          "    AND ci_builds.status = 'running' " \
          "    AND ci_builds.updated_at < NOW() - INTERVAL '1 hour'".freeze

        PER_RUNNER_QUERY =
          "SELECT " \
          "  ci_builds.runner_id, " \
          "  ci_runners.is_shared, " \
          "  projects.mirror, " \
          "  projects.pending_delete, " \
          "  projects.mirror_trigger_builds, " \
          "  COUNT(*) AS count " \
          "  FROM ci_builds " \
          "  JOIN ci_runners " \
          "    ON ci_runners.id = ci_builds.runner_id " \
          "  JOIN projects " \
          "    ON projects.id = ci_builds.gl_project_id " \
          "  WHERE ci_builds.type = 'Ci::Build' " \
          "    AND ci_builds.status = 'running' " \
          "  GROUP BY " \
          "    ci_builds.runner_id, " \
          "    projects.mirror, " \
          "    projects.pending_delete, " \
          "    projects.mirror_trigger_builds, " \
          "    ci_runners.is_shared".freeze

        def run
          results = {}

          results.merge!(get_builds(BUILDS_QUERY))

          results[:not_updated_last_hour] = get_general(NOT_UPDATED_RUNNING_BUILDS_QUERY)
          results[:per_runner] = get_per_runner(PER_RUNNER_QUERY)
          results
        end

        private

        def get_per_runner(query)
          results = []

          connection.exec(query).each do |row|
            results.push(
              runner: row["runner_id"].to_s,
              shared_runner: row["is_shared"] == "t" ? "yes" : "no",
              mirror: row["mirror"] == "t" ? "yes" : "no",
              pending_delete: row["pending_delete"] == "t" ? "yes" : "no",
              mirror_trigger_builds: row["mirror_trigger_builds"] == "t" ? "yes" : "no",
              value: row["count"].to_i
            )
          end

          results
        rescue PG::UndefinedTable, PG::UndefinedColumn
          []
        end

        def get_general(query)
          connection.exec(query)[0]["count"].to_i
        rescue PG::UndefinedTable, PG::UndefinedColumn
          0
        end

        def get_builds(query)
          results = { pending_builds: [], created_builds: [] }

          connection.exec(query).each do |row|
            shared_runners = row["shared_runners_enabled"] == "t" ? "yes" : "no"
            namespace = row["path"]
            value = row["count"].to_i

            if row["status"] == "pending"
              results[:pending_builds].push(namespace: namespace, shared_runners: shared_runners, value: value)
            elsif row["status"] == "created"
              results[:created_builds].push(namespace: namespace, shared_runners: shared_runners, value: value)
            end
          end

          results
        rescue PG::UndefinedTable, PG::UndefinedColumn
          {}
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
          other_value = { "yes" => 0, "no" => 0 }
          results_list.each do |metric|
            shared_runners = metric[:shared_runners]
            namespace = metric[:namespace]
            value = metric[:value]
            if value < 10
              other_value[shared_runners] += value
              value = other_value[shared_runners]
              namespace = ""
            end
            @metrics.add(metric_name,
                         value,
                         namespace: namespace,
                         shared_runners: shared_runners)
          end
        end

        def ci_stale_builds_metrics
          @metrics.add("ci_builds_stale", @results[:not_updated_last_hour], status: "running", when: "last_hour")
        end

        def metrics_per_runner
          @results[:per_runner].each do |metric|
            @metrics.add("ci_running_builds",
                         metric[:value],
                         runner: metric[:runner],
                         shared_runner: metric[:shared_runner],
                         mirror: metric[:mirror],
                         pending_delete: metric[:pending_delete],
                         mirror_trigger_builds: metric[:mirror_trigger_builds])
          end
        end
      end
    end
  end
end
