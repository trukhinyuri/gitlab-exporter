module GitLab
  module Monitor
    module Database
      # A helper class that executes the query its given and returns an int of
      # the row count
      # This class works under the assumption you do COUNT(*) queries, define
      # queries in the QUERIES constant. If in doubt how these work, read
      # #construct_query
      class RowCountCollector < Base
        QUERIES = {
          award_emoji: { select: :award_emoji },
          boards: { select: :boards },
          ci_builds: { select: :ci_builds },
          ci_commits: { select: :ci_commits },
          active_ci_runners: { select: :ci_runners, where: "active=true" },
          inactive_ci_runners: { select: :ci_runners, where: "active=false" },
          ci_variables: { select: :ci_variables },
          deployments: { select: :deployments },
          environments: { select: :environments },
          events: { select: :events },
          fork_count: { select: :forked_project_links },
          issues: { select: :issues, where: "deleted_at IS NULL" },
          keys: { select: :keys },
          labels: { select: :labels },
          merge_requests: { select: :merge_requests, where: "deleted_at IS NULL" },
          milestones: { select: :milestones },
          groups: { select: :namespaces, where: "type='Group'" },
          project_count: { select: :projects, where: "pending_delete=false" },
          soft_deleted_projects: { select: :projects, where: "pending_delete=true" },
          orphaned_projects: {
            select: :projects,
            joins: "LEFT JOIN namespaces ON projects.namespace_id = namespaces.id",
            where: "namespaces.id IS NULL"
          },
          soft_deleted_namespaces: { select: :namespaces, where: "deleted_at IS NOT NULL" },
          active_project_services: { select: :services, where: "active=true" },
          personal_snippets: { select: :snippets, where: "type='PersonalSnippet'" },
          project_snippets: { select: :snippets, where: "type='ProjectSnippet'" },
          user_notes: { select: :notes, where: "system=false" },
          system_note: { select: :notes, where: "system=true" },
          starred_projects: { select: :users_star_projects },
          user_count: { select: :users }
        }.freeze

        def run
          results = Hash.new(0)

          QUERIES.each do |key, query|
            results[key] = execute(query)
          end

          results
        end

        private

        def execute(query)
          connection.exec(construct_query(query))[0]["count"]
        rescue PG::UndefinedTable, PG::UndefinedColumn
          0
        end

        # Not private so I can test it without meta programming tricks
        def construct_query(query)
          query_string = "SELECT COUNT(*) FROM #{query[:select]} "
          query_string << "#{query[:joins]} "       if query[:joins]
          query_string << "WHERE #{query[:where]}"  if query[:where]
          query_string << ";"
        end
      end

      # The prober which is called when gathering metrics
      class RowCountProber
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics = metrics
          @collector = RowCountCollector.new(connection_string: opts[:connection_string])
        end

        def probe_db
          return self unless @collector.connected?

          results = @collector.run
          results.each do |key, value|
            @metrics.add("db_rows_count", value.to_i, query_name: key.to_s)
          end

          self
        end

        def write_to(target)
          target.write(@metrics.to_s)
        end
      end
    end
  end
end
