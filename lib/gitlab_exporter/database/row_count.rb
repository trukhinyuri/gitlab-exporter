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
            where: "ghost IS NULL AND bot_type IS NULL",
            fields: {
              admin:        {},
              external:     {},
              state:        {},
              access_level: { definition: "COALESCE(u.access_level, 0)" }
            }
          },
          projects: {
            select: :projects,
            fields: {
              visibility_level: {},
              archived:         {}
            }
          },
          groups: {
            select: :namespaces,
            fields: {
              visibility_level: {},
              root:             { definition: "(parent_id IS NULL)" }
            }
          }
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
            tm = PG::BasicTypeMapForResults.new(conn)

            # Remove warning message:
            # Warning: no type cast defined for type "name" with oid 19.
            # Please cast this type explicitly to TEXT to be safe for future changes.
            # Warning: no type cast defined for type "regproc" with oid 24.
            # Please cast this type explicitly to TEXT to be safe for future changes.
            [{ "type": "text", "oid": 19 }, { "type": "int4", "oid": 24 }].each do |value|
              old_coder = tm.coders.find { |c| c.name == value[:type] }
              tm.add_coder(old_coder.dup.tap { |c| c.oid = value[:oid] })
            end

            conn.exec(query).map_types!(tm)
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
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics = metrics
          @collector = RowCountCollector.new(
            connection_string: opts[:connection_string],
            selected_queries: opts[:selected_queries]
          )
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
