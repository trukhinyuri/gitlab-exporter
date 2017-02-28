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

        RUNNING_PER_SHARED_RUNNER_QUERY =
          "SELECT " \
          "  ci_builds.runner_id, " \
          "  COUNT(*) AS count " \
          "  FROM ci_builds " \
          "  WHERE ci_builds.type = 'Ci::Build' " \
          "    AND ci_builds.status = 'running' " \
          "    AND ci_builds.runner_id IN (%s) " \
          "  GROUP BY " \
          "    ci_builds.runner_id".freeze

        RUNNING_FOR_MIRRORS_PER_SHARED_RUNNER_QUERY =
          "SELECT ci_builds.runner_id, COUNT(*) AS count " \
          "  FROM ci_builds " \
          "  JOIN projects " \
          "    ON projects.id = ci_builds.gl_project_id " \
          "    AND projects.pending_delete = 'f' " \
          "    AND projects.mirror = 't' " \
          "    AND projects.mirror_trigger_builds = 't' " \
          "  WHERE ci_builds.type = 'Ci::Build' " \
          "    AND ci_builds.status = 'running' " \
          "    AND ci_builds.runner_id IN (%s) " \
          "  GROUP BY " \
          "    ci_builds.runner_id".freeze

        def run
          results = {}

          results.merge!(get_builds(BUILDS_QUERY))

          results[:not_updated_last_hour] = get_general(NOT_UPDATED_RUNNING_BUILDS_QUERY)
          results[:per_runner] = get_per_shared_runner(RUNNING_PER_SHARED_RUNNER_QUERY)
          results[:per_runner_mirrors] = get_per_shared_runner(RUNNING_FOR_MIRRORS_PER_SHARED_RUNNER_QUERY)
          results
        end

        private

        def get_per_shared_runner(query)
          return {} unless shared_runners_ids.count > 0
          query = query % shared_runners_ids.join(", ")

          builds = begin
            result = connection.exec(query)
            result.map { |v| [v["runner_id"].to_i, v["count"].to_i] }.to_h
          rescue PG::UndefinedTable, PG::UndefinedColumn
            {}
          end

          results = {}
          shared_runners_ids.each do |id|
            results[id] = builds[id] || 0
          end

          results
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

        def shared_runners_ids
          @shared_runners_ids ||= find_shared_runners_ids
        end

        def find_shared_runners_ids
          shared_runners_result = connection.exec("SELECT id FROM ci_runners WHERE ci_runners.is_shared = 't'")
          return [] unless shared_runners_result.count > 0
          shared_runners_result.map { |v| v["id"].to_i }
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
          @results[:per_runner].each do |key, value|
            all = value
            for_mirrors = @results[:per_runner_mirrors][key]
            not_for_mirrors = all - for_mirrors
            @metrics.add("ci_builds_per_runner", not_for_mirrors, status: "running", runner: key, mirrors: 0)
            @metrics.add("ci_builds_per_runner", for_mirrors, status: "running", runner: key, mirrors: 1)
          end
        end
      end
    end
  end
end
