module GitLab
  module Monitor
    module Database
      # A helper class that executes the query its given and returns an int of
      # the row count
      # This class works under the assumption you do COUNT(*) queries
      class RowCountCollector < Base
        QUERIES = [
          :soft_deleted_projects,
          :soft_deleted_namespaces,
          :orphaned_projects
        ].freeze

        def run
          results = Hash.new(0)

          QUERIES.each do |query|
            results[query] = execute(query)
          end

          results
        end

        private

        def execute(query)
          connection.exec(send(query))[0]["count"]
        end

        def soft_deleted_projects
          <<-SQL
            SELECT COUNT(*) FROM projects
            WHERE pending_delete=true;
          SQL
        end

        def soft_deleted_namespaces
          <<-SQL
            SELECT COUNT(*) FROM namespaces
            WHERE deleted_at IS NOT NULL;
          SQL
        end

        def orphaned_projects
          <<-SQL
            SELECT COUNT(*) FROM projects
            LEFT JOIN namespaces ON projects.namespace_id = namespaces.id
            WHERE namespaces.id IS NULL;
          SQL
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
