# frozen_string_literal: true

require "faraday"
require "json"

module GitLab
  module Exporter
    # Exports GitLab specific Elasticsearch metrics.
    #
    # For generic operational metrics, see elasticsearch_exporter.
    # https://github.com/prometheus-community/elasticsearch_exporter
    class ElasticsearchProber
      MIGRATION_STATE_MAP = {
        unknown: -9,
        # TODO: failed: -1
        pending: 0,
        running: 1,
        halted: 2,
        completed: 3
      }.freeze

      def initialize(metrics: PrometheusMetrics.new, logger: nil, **opts)
        @metrics = metrics
        @logger  = logger
        @opts    = opts
      end

      # Probes the state of Advanced Search Migrations
      # https://docs.gitlab.com/ee/integration/elasticsearch.html#advanced-search-migrations
      def probe_migrations
        elastic_probe do |conn|
          resp = conn.get "/gitlab-*-migrations/_search"
          return unless resp.status == 200

          JSON.parse(resp.body).dig("hits", "hits").each do |hit|
            @metrics.add(
              "elasticsearch_migrations_info", 1, # 1 is a noop.
              state: inferred_migration_state(hit.fetch("_source")),
              name: hit.fetch("_id")
            )
          end
        end
      rescue StandardError => e
        @logger&.error "ElasticsearchProper encountered an error: #{e}"
      end

      private

      def elastic_probe
        yield Faraday.new(@opts.fetch(:url), @opts.fetch(:options, {}))
      end

      def inferred_migration_state(migration)
        return :pending if migration["started_at"] == ""

        if migration["started_at"] != "" && migration["completed_at"] == "" && !migration.dig("state", "halted")
          return :running
        end

        return :completed if migration["completed"]
        return :halted if migration.dig("state", "halted")

        @logger&.error("Elasticsearch probe doesn't know the state of a migration")
        :unknown
      end
    end
  end
end
