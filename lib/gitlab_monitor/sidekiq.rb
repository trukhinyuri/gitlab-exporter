require "sidekiq/api"
require "digest"

module GitLab
  module Monitor
    # A prober for Sidekiq queues
    #
    # It takes the Redis URL Sidekiq is connected to
    class SidekiqProber
      QUEUE_JOB_STATS_SCRIPT = File.read(File.expand_path("#{__FILE__}/../sidekiq_queue_job_stats.lua")).freeze
      QUEUE_JOB_STATS_SHA    = Digest::SHA1.hexdigest(QUEUE_JOB_STATS_SCRIPT).freeze

      def initialize(opts, metrics: PrometheusMetrics.new)
        @opts    = opts
        @metrics = metrics

        Sidekiq.configure_client do |config|
          config.redis = { url: opts[:redis_url], namespace: "resque:gitlab" }
        end

        ensure_queue_job_stats_script_loaded
      end

      def probe_queues
        return self unless connected?

        Sidekiq::Queue.all.each do |queue|
          @metrics.add("sidekiq_queue_size", queue.size, name: queue.name)
          @metrics.add("sidekiq_queue_latency", queue.latency, name: queue.name)
        end

        self
      end

      def probe_jobs # rubocop:disable Metrics/MethodLength
        return self unless connected?

        job_stats = {}

        Sidekiq::Queue.all.each do |queue|
          begin
            Sidekiq.redis do |conn|
              stats = conn.evalsha(QUEUE_JOB_STATS_SHA, ["queue:#{queue.name}"])
              job_stats.merge!(stats.to_h)
            end
          rescue Redis::CommandError # Could happen if the script exceeded the maximum run time (5 seconds by default)
            # FIXME: Should we call SCRIPT KILL?
            return self
          end
        end

        job_stats.each do |class_name, count|
          @metrics.add("sidekiq_enqueued_jobs_count", count, name: class_name)
        end

        self
      end

      def probe_workers
        return self unless connected?

        worker_stats = Hash.new(0)

        Sidekiq::Workers.new.map do |_pid, _tid, work|
          job_klass = work["payload"]["class"]

          worker_stats[job_klass] += 1
        end

        worker_stats.each do |class_name, count|
          @metrics.add("sidekiq_running_jobs_count", count, name: class_name)
        end

        self
      end

      def probe_retries
        return self unless connected?

        retry_stats = Hash.new(0)

        Sidekiq::RetrySet.new.map do |job|
          retry_stats[job.klass] += 1
        end

        retry_stats.each do |class_name, count|
          @metrics.add("sidekiq_jobs_to_be_retried_count", count, name: class_name)
        end

        self
      end

      def write_to(target)
        target.write(@metrics.to_s)
      end

      private

      def connected?
        @connected ||= begin
                         Sidekiq.redis do |conn|
                           conn.get("foo")
                         end
                         true
                       end
      rescue Redis::CannotConnectError # rubocop:disable Lint/HandleExceptions
        # Maybe we're trying connecting to a slave
      end

      def ensure_queue_job_stats_script_loaded
        return unless connected?

        Sidekiq.redis do |conn|
          next if conn.script(:exists, QUEUE_JOB_STATS_SHA)
          conn.script(:load, QUEUE_JOB_STATS_SCRIPT)
        end
      end
    end
  end
end
