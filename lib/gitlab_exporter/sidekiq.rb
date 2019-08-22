require "sidekiq/api"
require "digest"

module GitLab
  module Exporter
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
          config.redis = redis_options
        end

        ensure_queue_job_stats_script_loaded
      end

      def probe_stats
        return self unless connected?

        stats = Sidekiq::Stats.new

        @metrics.add("sidekiq_jobs_processed_total", stats.processed)
        @metrics.add("sidekiq_jobs_failed_total", stats.failed)
        @metrics.add("sidekiq_jobs_enqueued_size", stats.enqueued)
        @metrics.add("sidekiq_jobs_scheduled_size", stats.scheduled_size)
        @metrics.add("sidekiq_jobs_retry_size", stats.retry_size)
        @metrics.add("sidekiq_jobs_dead_size", stats.dead_size)

        @metrics.add("sidekiq_default_queue_latency_seconds", stats.default_queue_latency)
        @metrics.add("sidekiq_processes_size", stats.processes_size)
        @metrics.add("sidekiq_workers_size", stats.workers_size)

        self
      end

      def probe_queues
        return self unless connected?

        Sidekiq::Queue.all.each do |queue|
          @metrics.add("sidekiq_queue_size", queue.size, name: queue.name)
          @metrics.add("sidekiq_queue_latency_seconds", queue.latency, name: queue.name)
          @metrics.add("sidekiq_queue_paused", queue.paused? ? 1 : 0, name: queue.name)
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
          @metrics.add("sidekiq_enqueued_jobs", count, name: class_name)
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
          @metrics.add("sidekiq_running_jobs", count, name: class_name)
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
          @metrics.add("sidekiq_to_be_retried_jobs", count, name: class_name)
        end

        self
      end

      def probe_dead
        puts "[DEPRECATED] probe_dead is now considered obsolete and will be removed in future major versions,"\
             " please use probe_stats instead"

        return self unless connected?

        @metrics.add("sidekiq_dead_jobs", Sidekiq::Stats.new.dead_size)

        self
      end

      def write_to(target)
        target.write(@metrics.to_s)
      end

      private

      def redis_options
        options = {
          url: @opts[:redis_url],
          namespace: "resque:gitlab",
          connect_timeout: 1,
          reconnect_attempts: 0
        }

        options[:id] = nil unless redis_enable_client?
        options
      end

      def redis_enable_client?
        return true if @opts[:redis_enable_client].nil?

        @opts[:redis_enable_client]
      end

      def connected?
        @connected ||= begin
                         Sidekiq.redis do |conn|
                           conn.get("foo")
                         end
                         true
                       end
      rescue Redis::CannotConnectError, Redis::TimeoutError # rubocop:disable Lint/HandleExceptions
        # Maybe we're trying connecting to a slave
      end

      def ensure_queue_job_stats_script_loaded
        return unless connected?

        Sidekiq.redis do |conn|
          # Using administrative commands on conn directly (which is a Redis::Namespace)
          # will be removed in redis-namespace 2.0.
          next if conn.redis.script(:exists, QUEUE_JOB_STATS_SHA)
          conn.redis.script(:load, QUEUE_JOB_STATS_SCRIPT)
        end
      end
    end
  end
end
