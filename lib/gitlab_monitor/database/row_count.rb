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
          groups: { select: :namespaces, where: "type='Group'" },
          projects: { select: :projects, where: "pending_delete=false" },
          soft_deleted_projects: { select: :projects, where: "pending_delete=true" },
          orphaned_projects: {
            select: :projects,
            joins: "LEFT JOIN namespaces ON projects.namespace_id = namespaces.id",
            where: "namespaces.id IS NULL"
          },
          personal_snippets: { select: :snippets, where: "type='PersonalSnippet'" },
          project_snippets: { select: :snippets, where: "type='ProjectSnippet'" },
          users: { select: :users },
          active_runners: { select: :ci_runners, where: "active=true AND contacted_at >= NOW() - '1 day'::INTERVAL" },
          pages_domains: { select: :pages_domains }
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
