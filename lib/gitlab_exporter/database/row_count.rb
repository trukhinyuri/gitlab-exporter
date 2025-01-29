require "set"

module GitLab
  module Exporter
    module Database
      # A helper class that executes the query its given and returns an int of
      # the row count
      # This class works under the assumption you do COUNT(*) queries, define
      # queries in the QUERIES constant. If in doubt how these work, read
      # #construct_query
      class RowCountCollector < Base # rubocop:disable Metrics/ClassLength
        # We ignore mirrors with a next_execution_timestamp before
        # 2020-03-28 because this is when we stopped processing mirrors
        # for private projects on the free plan. Skipping those can
        # significantly improve query performance:
        # https://gitlab.com/gitlab-org/gitlab/-/issues/216252#note_334514544
        WHERE_MIRROR_ENABLED = <<~SQL.freeze
          projects.mirror = true
          AND projects.archived = false
          AND project_mirror_data.retry_count <= 14
          AND project_mirror_data.next_execution_timestamp > '2020-03-28'
        SQL

        MIRROR_QUERY = {
          select: :projects,
          joins: <<~SQL,
            INNER JOIN project_mirror_data ON project_mirror_data.project_id = projects.id
          SQL
          check: "SELECT 1 FROM information_schema.tables WHERE table_name='plans'"
        }.freeze

        CONTAINER_REPOSITORIES_CLEANUP_ENABLED_QUERY = {
          select: :container_repositories,
          joins: <<~SQL,
            INNER JOIN container_expiration_policies
            ON container_repositories.project_id = container_expiration_policies.project_id
          SQL
          where: "container_expiration_policies.enabled = TRUE"
        }.freeze

        QUERIES = {
          mirrors_ready_to_sync: MIRROR_QUERY.merge( # EE only
            where: <<~SQL
              #{WHERE_MIRROR_ENABLED}
              AND project_mirror_data.status NOT IN ('scheduled', 'started')
              AND project_mirror_data.next_execution_timestamp <= NOW()
            SQL
          ),
          mirrors_not_updated_recently: MIRROR_QUERY.merge( # EE only
            where: <<~SQL
              #{WHERE_MIRROR_ENABLED}
              AND project_mirror_data.status NOT IN ('scheduled', 'started')
              AND (project_mirror_data.next_execution_timestamp - project_mirror_data.last_update_at) <= '30 minutes'::interval
              AND project_mirror_data.last_update_at < NOW() - '30 minutes'::interval
            SQL
          ),
          mirrors_updated_very_recently: MIRROR_QUERY.merge( # EE only
            where: <<~SQL
              #{WHERE_MIRROR_ENABLED}
              AND project_mirror_data.status NOT IN ('scheduled', 'started')
              AND project_mirror_data.last_update_at >= NOW() - '30 seconds'::interval
            SQL
          ),
          mirrors_behind_schedule: MIRROR_QUERY.merge( # EE only
            where: <<~SQL
              #{WHERE_MIRROR_ENABLED}
              AND project_mirror_data.status NOT IN ('scheduled', 'started')
              AND project_mirror_data.next_execution_timestamp <= NOW() - '10 seconds'::interval
            SQL
          ),
          mirrors_scheduled_or_started: MIRROR_QUERY.merge( # EE only
            where: <<~SQL
              #{WHERE_MIRROR_ENABLED}
              AND project_mirror_data.status IN ('scheduled', 'started')
            SQL
          ),
          mirrors_scheduled: MIRROR_QUERY.merge( # EE only
            where: <<~SQL
              #{WHERE_MIRROR_ENABLED}
              AND project_mirror_data.status = 'scheduled'
            SQL
          ),
          mirrors_started: MIRROR_QUERY.merge( # EE only
            where: <<~SQL
              #{WHERE_MIRROR_ENABLED}
              AND project_mirror_data.status = 'started'
            SQL
          ),
          soft_deleted_projects: { select: :projects, where: "pending_delete=true" },
          orphaned_projects: {
            select: :projects,
            joins: "LEFT JOIN namespaces ON projects.namespace_id = namespaces.id",
            where: "namespaces.id IS NULL"
          },
          uploads: { select: :uploads },
          users: {
            select: :users,
            joins: "LEFT JOIN
              (
                SELECT
                  members.user_id,
                  MAX(access_level) as access_level
                FROM members
                GROUP BY members.user_id
              ) AS u
              ON users.id = u.user_id",
            where: "user_type = 0",
            fields: {
              admin: {},
              external: {},
              state: {},
              access_level: { definition: "COALESCE(u.access_level, 0)" }
            }
          },
          projects: {
            select: :projects,
            fields: {
              visibility_level: {},
              archived: {}
            }
          },
          namespaces: {
            select: :namespaces,
            fields: {
              type: {},
              visibility_level: {},
              root: { definition: "(parent_id IS NULL)" }
            }
          },
          container_repositories: { select: :container_repositories },
          container_repositories_delete_scheduled: { select: :container_repositories, where: "status = 0" },
          container_repositories_delete_failed: { select: :container_repositories, where: "status = 1" },
          container_repositories_delete_ongoing: { select: :container_repositories, where: "status = 2" },
          container_repositories_delete_staled: {
            select: :container_repositories,
            where: "status = 2 AND delete_started_at < (NOW() - INTERVAL '30 minutes')"
          },
          container_repositories_cleanup_enabled: CONTAINER_REPOSITORIES_CLEANUP_ENABLED_QUERY,
          container_repositories_cleanup_pending: CONTAINER_REPOSITORIES_CLEANUP_ENABLED_QUERY.merge(
            where: <<~SQL
              container_expiration_policies.enabled = TRUE
              AND container_repositories.expiration_policy_cleanup_status IN (0, 1)
              AND (container_repositories.expiration_policy_started_at IS NULL OR container_repositories.expiration_policy_started_at < container_expiration_policies.next_run_at)
              AND (container_expiration_policies.next_run_at < NOW())
            SQL
          ),
          container_repositories_cleanup_unfinished: CONTAINER_REPOSITORIES_CLEANUP_ENABLED_QUERY.merge(
            where: <<~SQL
              container_expiration_policies.enabled = TRUE
              AND container_repositories.expiration_policy_cleanup_status = 2
            SQL
          ),
          container_repositories_cleanup_unscheduled: CONTAINER_REPOSITORIES_CLEANUP_ENABLED_QUERY.merge(
            where: <<~SQL
              container_expiration_policies.enabled = TRUE
              AND container_repositories.expiration_policy_cleanup_status = 0
            SQL
          ),
          container_repositories_cleanup_scheduled: CONTAINER_REPOSITORIES_CLEANUP_ENABLED_QUERY.merge(
            where: <<~SQL
              container_expiration_policies.enabled = TRUE
              AND container_repositories.expiration_policy_cleanup_status = 1
            SQL
          ),
          container_repositories_cleanup_ongoing: {
            select: :container_repositories,
            where: "expiration_policy_cleanup_status = 3"
          },
          container_repositories_cleanup_staled: {
            select: :container_repositories,
            where: <<~SQL
              expiration_policy_cleanup_status = 3
              AND (expiration_policy_started_at < (NOW() - INTERVAL '35 minutes') OR expiration_policy_started_at IS NULL)
            SQL
          }
        }.freeze

        def initialize(selected_queries: nil, **args)
          super(**args)

          @selected_queries = Set.new(selected_queries.map(&:to_sym)) unless selected_queries.nil?
        end

        def run
          results = Hash.new(0)

          QUERIES.each do |key, query_hash|
            next if query_hash[:check] && !successful_check?(query_hash[:check])
            next if !@selected_queries.nil? && !@selected_queries.include?(key)

            results[key] = count_from_query_hash(query_hash)
          end

          results
        end

        private

        def count_from_query_hash(query_hash)
          result = execute(construct_query(query_hash))
          return [{ "count": 0, "labels": {} }] unless result

          result.map do |row|
            labels = {}
            (query_hash[:fields] || []).each do |key, _| labels[key] = row[key.to_s] end
            { "count": row["count"], "labels": labels }
          end
        end

        def successful_check?(query)
          result = execute("SELECT EXISTS (#{query})")
          return unless result

          result[0]["exists"]
        end

        def execute(query)
          with_connection_pool do |conn|
            conn.exec(query)
          end
        rescue PG::UndefinedTable, PG::UndefinedColumn
          nil
        end

        # Not private so I can test it without meta programming tricks
        def construct_query(query)
          query_string = "SELECT COUNT(*)"
          (query[:fields] || []).each do |key, value|
            query_string << ", "
            query_string << "(#{value[:definition]}) AS " if value[:definition]
            query_string << key.to_s
          end
          query_string << " FROM #{query[:select]}"
          query_string << " #{query[:joins]}"       if query[:joins]
          query_string << " WHERE #{query[:where]}" if query[:where]
          query_string << " GROUP BY " + query[:fields].keys.join(", ") if query[:fields]
          query_string << ";"
        end
      end

      # The prober which is called when gathering metrics
      class RowCountProber
        def initialize(metrics: PrometheusMetrics.new, **opts)
          @metrics = metrics
          @collector = RowCountCollector.new(**opts)
        end

        def probe_db
          results = @collector.run
          results.each do |query_name, result|
            labels = { query_name: query_name.to_s }
            result.each do |row|
              @metrics.add("gitlab_database_rows", row[:count].to_f, **labels, **row[:labels])
            end
          end

          self
        rescue PG::ConnectionBad
          self
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end
      end
    end
  end
end
