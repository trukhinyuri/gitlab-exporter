module GitLab
  module Monitor
    module Database
      # A helper class that executes the query its given and returns an int of
      # the row count
      # This class works under the assumption you do COUNT(*) queries
      class RowCountCollector < Base
        QUERIES = [
          :orphaned_projects,
          :soft_deleted_projects,
          :orphaned_soft_deleted_projects
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

        def orphaned_projects
          <<-SQL
            SELECT COUNT(*) FROM projects
            WHERE namespace_id IS NULL;
          SQL
        end

        def soft_deleted_projects
          <<-SQL
            SELECT COUNT(*) FROM projects
            WHERE pending_delete=true;
          SQL
        end

        def orphaned_soft_deleted_projects
          <<-SQL
            SELECT COUNT(*) FROM projects
            WHERE pending_delete=true AND namespace_id IS NULL;
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
            @metrics.add("#{key}_count", value.to_i)
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
