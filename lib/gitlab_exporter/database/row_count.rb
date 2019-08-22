require "set"

module GitLab
  module Exporter
    module Database
      # A helper class that executes the query its given and returns an int of
      # the row count
      # This class works under the assumption you do COUNT(*) queries, define
      # queries in the QUERIES constant. If in doubt how these work, read
      # #construct_query
      class RowCountCollector < Base
        WHERE_MIRROR_ENABLED = <<~SQL.freeze
          projects.mirror = true
          AND project_mirror_data.retry_count <= 14
          AND (projects.visibility_level = 20 OR plans.name IN ('early_adopter', 'bronze', 'silver', 'gold'))
        SQL

        MIRROR_QUERY = {
          select: :projects,
          joins:  <<~SQL,
            INNER JOIN project_mirror_data ON project_mirror_data.project_id = projects.id
            INNER JOIN namespaces ON projects.namespace_id = namespaces.id
            LEFT JOIN plans ON namespaces.plan_id = plans.id
          SQL
          check: "SELECT 1 FROM information_schema.tables WHERE table_name='plans'"
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
          uploads: { select: :uploads }
        }.freeze

        def initialize(args)
          super(args)

          @selected_queries = Set.new(args[:selected_queries].map(&:to_sym)) unless args[:selected_queries].nil?
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
          return 0 unless result

          result[0]["count"]
        end

        def successful_check?(query)
          result = execute("SELECT EXISTS (#{query})")
          return unless result

          result[0]["exists"] == "t"
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
          @collector = RowCountCollector.new(
            connection_string: opts[:connection_string],
            selected_queries: opts[:selected_queries]
          )
        end

        def probe_db
          results = @collector.run
          results.each do |key, value|
            @metrics.add("gitlab_database_rows", value.to_i, query_name: key.to_s)
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
