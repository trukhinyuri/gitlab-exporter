module GitLab
  module Exporter
    module Database
      # A helper class to collect remote mirrors metrics.
      class RemoteMirrorsCollector < Base
        QUERY = <<~SQL.freeze
          SELECT project_id, url,
          EXTRACT(EPOCH FROM last_successful_update_at) AS last_successful_update_at,
          EXTRACT(EPOCH FROM last_update_at) AS last_update_at
          FROM remote_mirrors WHERE project_id IN (%s) AND enabled = 't'
        SQL

        def initialize(args)
          super(args)

          @project_ids = args[:project_ids]
        end

        def run
          return if @project_ids.nil? || @project_ids.empty?

          execute(QUERY % [@project_ids.join(",")]) # rubocop:disable Style/FormatString
        end

        private

        def execute(query)
          with_connection_pool do |conn|
            conn.exec(query)
          end
        rescue PG::UndefinedTable, PG::UndefinedColumn
          nil
        end
      end

      # The prober which is called when gathering metrics
      class RemoteMirrorsProber
        def initialize(opts, metrics: PrometheusMetrics.new)
          @metrics = metrics
          @collector = RemoteMirrorsCollector.new(
            connection_string: opts[:connection_string],
            project_ids: opts[:project_ids]
          )
        end

        def probe_db # rubocop:disable Metrics/MethodLength
          results = @collector.run
          results.to_a.each do |row|
            @metrics.add(
              "project_remote_mirror_last_successful_update_time_seconds",
              row["last_successful_update_at"].to_f,
              project_id: row["project_id"],
              url: row["url"]
            )
            @metrics.add(
              "project_remote_mirror_last_update_time_seconds",
              row["last_update_at"].to_f,
              project_id: row["project_id"],
              url: row["url"]
            )
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
