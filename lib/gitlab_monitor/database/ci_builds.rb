module GitLab
  module Monitor
    module Database
      # A helper class to collect blocked queries
      class CiBuildsCollector < Base
        TOTAL_BUILDS_QUERY =
          "SELECT p.shared_runners_enabled, b.status, COUNT(*) AS count FROM ci_builds AS b JOIN projects AS p " \
          "ON p.id = b.gl_project_id WHERE b.type = 'Ci::Build' AND b.status IN ('created', 'pending', 'running') " \
          "GROUP BY p.shared_runners_enabled, b.status".freeze

        NOT_UPDATED_RUNNING_BUILDS_QUERY =
          "SELECT COUNT(*) AS count FROM ci_builds AS b WHERE b.type = 'Ci::Build' AND b.status = 'running' " \
          "AND b.updated_at < NOW() - INTERVAL '1 hour'".freeze

        RUNNING_PER_SHARED_RUNNER_QUERY =
          "SELECT b.runner_id, COUNT(*) AS count " \
          "FROM ci_builds AS b " \
          "WHERE b.type = 'Ci::Build' AND b.status = 'running' AND b.runner_id IN (%s) " \
          "GROUP BY b.runner_id".freeze

        RUNNING_FOR_MIRRORS_PER_SHARED_RUNNER_QUERY =
          "SELECT b.runner_id, COUNT(*) AS count " \
          "FROM ci_builds AS b " \
          "JOIN projects AS p " \
          "ON p.id = b.gl_project_id AND p.pending_delete = 'f' AND p.mirror = 't' AND p.mirror_trigger_builds = 't' " \
          "WHERE b.type = 'Ci::Build' AND b.status = 'running' AND b.runner_id IN (%s) " \
          "GROUP BY b.runner_id".freeze

        def run
          results = {}

          total = get_shared_enabled_and_status_grouped(TOTAL_BUILDS_QUERY)
          results[:created] = total[:created]
          results[:pending] = total[:pending]
          results[:running] = total[:running]

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

        def get_shared_enabled_and_status_grouped(query)
          results = { created: { shared_enabled: 0, shared_disabled: 0 },
                      pending: { shared_enabled: 0, shared_disabled: 0 },
                      running: { shared_enabled: 0, shared_disabled: 0 } }

          connection.exec(query).each do |row|
            shared_enabled = row["shared_runners_enabled"] == "t"
            status = row["status"].to_sym

            results[status][:shared_enabled] = row["count"].to_i if shared_enabled
            results[status][:shared_disabled] = row["count"].to_i unless shared_enabled
          end

          results
        rescue PG::UndefinedTable, PG::UndefinedColumn
          { created: { shared_enabled: 0, shared_disabled: 0 },
            pending: { shared_enabled: 0, shared_disabled: 0 },
            running: { shared_enabled: 0, shared_disabled: 0 } }
        end

        def shared_runners_ids
          @shared_runners_ids ||= find_shared_runners_ids
        end

        def find_shared_runners_ids
          shared_runners_result = connection.exec("SELECT id FROM ci_runners AS r WHERE r.is_shared = 't'")
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

          metrics_total
          metrics_per_runner

          self
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end

        private

        def metrics_total
          @metrics.add("ci_builds_total", @results[:created][:shared_enabled], status: "created",
                                                                               shared_runners_enabled_projects: 1)
          @metrics.add("ci_builds_total", @results[:created][:shared_disabled], status: "created",
                                                                                shared_runners_enabled_projects: 0)
          @metrics.add("ci_builds_total", @results[:pending][:shared_enabled], status: "pending",
                                                                               shared_runners_enabled_projects: 1)
          @metrics.add("ci_builds_total", @results[:pending][:shared_disabled], status: "pending",
                                                                                shared_runners_enabled_projects: 0)
          @metrics.add("ci_builds_total", @results[:running][:shared_enabled], status: "running",
                                                                               shared_runners_enabled_projects: 1)
          @metrics.add("ci_builds_total", @results[:running][:shared_disabled], status: "running",
                                                                                shared_runners_enabled_projects: 0)

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
