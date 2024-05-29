require "sidekiq/api"
require "sidekiq/scheduled"
require "digest"

module GitLab
  module Exporter
    # A prober for Sidekiq queues
    #
    # It takes the Redis URL Sidekiq is connected to
    class SidekiqProber # rubocop:disable Metrics/ClassLength
      # The maximum depth (from the head) of each queue to probe. Probing the
      # entirety of a very large queue will take longer and run the risk of
      # timing out. But when we have a very large queue, we are most in need of
      # reliable metrics. This trades off completeness for predictability by
      # only taking a limited amount of items from the head of the queue.
      PROBE_JOBS_LIMIT = 1_000

      POOL_SIZE = 3

      # This timeout is configured to higher interval than scrapping
      # of Prometheus to ensure that connection is kept instead of
      # needed to be re-initialized
      POOL_TIMEOUT = 90

      # Lock for Sidekiq.redis which we need to modify, but is not concurrency safe.
      SIDEKIQ_REDIS_LOCK = Mutex.new

      PrometheusMetrics.describe("sidekiq_enqueued_jobs",
                                 "Total number of jobs enqueued by class name. Only inspects the first #{PROBE_JOBS_LIMIT} jobs per queue.") # rubocop:disable Layout/LineLength

      def self.connection_pool
        @@connection_pool ||= Hash.new do |h, connection_hash| # rubocop:disable Style/ClassVars
          config = connection_hash.merge(pool_timeout: POOL_TIMEOUT, size: POOL_SIZE)

          h[connection_hash] = Sidekiq::RedisConnection.create(config)
        end
      end

      def initialize(metrics: PrometheusMetrics.new, logger: nil, **opts)
        @opts    = opts
        @metrics = metrics
        @logger  = logger
      end

      def probe_stats
        with_sidekiq do
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
        end

        self
      end

      def probe_queues
        with_sidekiq do
          Sidekiq::Queue.all.each do |queue|
            @metrics.add("sidekiq_queue_size", queue.size, name: queue.name)
            @metrics.add("sidekiq_queue_latency_seconds", queue.latency, name: queue.name)
            @metrics.add("sidekiq_queue_paused", queue.paused? ? 1 : 0, name: queue.name)
          end
        end

        self
      end

      def probe_jobs
        puts "[REMOVED] probe_jobs is now considered obsolete and does not emit any metrics,"\
             " please use probe_jobs_limit instead"

        self
      end

      def probe_future_sets
        now = Time.now.to_f
        with_sidekiq do
          Sidekiq.redis do |conn|
            Sidekiq::Scheduled::SETS.each do |set|
              # Default to 0; if all jobs are due in the future, there is no "negative" delay.
              delay = 0

              _job, timestamp = conn.zrangebyscore(set, "-inf", now.to_s, limit: [0, 1], withscores: true).first
              delay = now - timestamp if timestamp

              @metrics.add("sidekiq_#{set}_set_processing_delay_seconds", delay)

              # zcount is O(log(N)) (prob. binary search), so is still quick even with large sets
              @metrics.add("sidekiq_#{set}_set_backlog_count",
                           conn.zcount(set, "-inf", now.to_s))
            end
          end
        end
      end

      # Count worker classes present in Sidekiq queues. This only looks at the
      # first PROBE_JOBS_LIMIT jobs in each queue. This means that we run a
      # single LRANGE command for each queue, which does not block other
      # commands. For queues over PROBE_JOBS_LIMIT in size, this means that we
      # will not have completely accurate statistics, but the probe performance
      # will also not degrade as the queue gets larger.
      def probe_jobs_limit
        with_sidekiq do
          job_stats = Hash.new(0)

          Sidekiq::Queue.all.each do |queue|
            Sidekiq.redis do |conn|
              conn.lrange("queue:#{queue.name}", 0, PROBE_JOBS_LIMIT).each do |job|
                job_class = Sidekiq.load_json(job)["class"]

                job_stats[job_class] += 1
              end
            end
          end

          job_stats.each do |class_name, count|
            @metrics.add("sidekiq_enqueued_jobs", count, name: class_name)
          end
        end

        self
      end

      def probe_workers
        with_sidekiq do
          worker_stats = Hash.new(0)

          Sidekiq::Workers.new.map do |_pid, _tid, work|
            job_klass = work["payload"]["class"]

            worker_stats[job_klass] += 1
          end

          worker_stats.each do |class_name, count|
            @metrics.add("sidekiq_running_jobs", count, name: class_name)
          end
        end

        self
      end

      def probe_retries
        with_sidekiq do
          retry_stats = Hash.new(0)

          Sidekiq::RetrySet.new.map do |job|
            retry_stats[job.klass] += 1
          end

          retry_stats.each do |class_name, count|
            @metrics.add("sidekiq_to_be_retried_jobs", count, name: class_name)
          end
        end

        self
      end

      def probe_dead
        puts "[DEPRECATED] probe_dead is now considered obsolete and will be removed in future major versions,"\
             " please use probe_stats instead"

        with_sidekiq do
          @metrics.add("sidekiq_dead_jobs", Sidekiq::Stats.new.dead_size)
        end

        self
      end

      def write_to(target)
        target.write(@metrics.to_s)
      end

      private

      def with_sidekiq
        SIDEKIQ_REDIS_LOCK.synchronize {
          Sidekiq.configure_client do |config|
            config.redis = self.class.connection_pool[redis_options]
          end

          return unless connected?

          yield
        }
      end

      def redis_options
        options = {
          url: @opts[:redis_url],
          sentinels: redis_sentinel_options,
          connect_timeout: 1,
          reconnect_attempts: 0
        }

        %i[username password].each do |credential|
          options[credential] = @opts[:"redis_#{credential}"] if @opts.key?(:"redis_#{credential}")
        end

        options[:id] = nil unless redis_enable_client?
        options
      end

      def redis_sentinel_options
        sentinels = @opts[:redis_sentinels]

        return sentinels unless sentinels.is_a?(Array)

        sentinels.each do |sentinel_config|
          sentinel_config[:username] = @opts[:redis_sentinel_username] if @opts.key?(:redis_sentinel_username)
          sentinel_config[:password] = @opts[:redis_sentinel_password] if @opts.key?(:redis_sentinel_password)
        end

        sentinels
      end

      def redis_enable_client?
        return true if @opts[:redis_enable_client].nil?

        @opts[:redis_enable_client]
      end

      def connected?
        return @connected unless @connected.nil?

        Sidekiq.redis do |conn|
          @connected = (conn.ping == "PONG")
        end
      rescue Redis::BaseConnectionError => e
        @logger&.error "Error connecting to the Redis: #{e}"
        pool = self.class.connection_pool[redis_options]
        pool.reload(&:close)
        @connected = false
      end
    end
  end
end
