require "sidekiq/api"
require "sidekiq/scheduled"
require "digest"

module GitLab
  module Exporter
    # A prober for Sidekiq queues
    #
    # It takes the Redis URL Sidekiq is connected to
    # rubocop:disable Metrics/ClassLength
    class SidekiqProber
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

        @probe_namespaced = !!opts[:probe_namespaced] # rubocop:disable Style/DoubleNegation
        @probe_non_namespaced = !!opts[:probe_non_namespaced] # rubocop:disable Style/DoubleNegation

        # to maintain backward compatibility if the config is missing values
        @probe_namespaced = true if opts[:probe_namespaced].nil? && opts[:probe_non_namespaced].nil?
      end

      def probe_stats
        with_sidekiq { _probe_stats } if @probe_namespaced
        with_sidekiq(false) { _probe_stats(false) } if @probe_non_namespaced

        self
      end

      def probe_queues
        with_sidekiq { _probe_queues } if @probe_namespaced
        with_sidekiq(false) { _probe_queues(false) } if @probe_non_namespaced

        self
      end

      def probe_jobs
        puts "[REMOVED] probe_jobs is now considered obsolete and does not emit any metrics,"\
             " please use probe_jobs_limit instead"

        self
      end

      def probe_future_sets
        with_sidekiq { _probe_future_sets } if @probe_namespaced
        with_sidekiq(false) { _probe_future_sets(false) } if @probe_non_namespaced
      end

      # Count worker classes present in Sidekiq queues. This only looks at the
      # first PROBE_JOBS_LIMIT jobs in each queue. This means that we run a
      # single LRANGE command for each queue, which does not block other
      # commands. For queues over PROBE_JOBS_LIMIT in size, this means that we
      # will not have completely accurate statistics, but the probe performance
      # will also not degrade as the queue gets larger.
      def probe_jobs_limit
        with_sidekiq { _probe_jobs_limit } if @probe_namespaced
        with_sidekiq(false) { _probe_jobs_limit(false) } if @probe_non_namespaced

        self
      end

      def probe_workers
        with_sidekiq { _probe_workers } if @probe_namespaced
        with_sidekiq(false) { _probe_workers(false) } if @probe_non_namespaced

        self
      end

      def probe_retries
        with_sidekiq { _probe_retries } if @probe_namespaced
        with_sidekiq(false) { _probe_retries(false) } if @probe_non_namespaced

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

      def _probe_workers(namespace = true)
        labels = add_namespace_labels? ? { namespaced: namespace } : {}
        worker_stats = Hash.new(0)

        Sidekiq::Workers.new.map do |_pid, _tid, work|
          job_klass = work["payload"]["class"]

          worker_stats[job_klass] += 1
        end

        worker_stats.each do |class_name, count|
          @metrics.add("sidekiq_running_jobs", count, **labels.merge({ name: class_name }))
        end
      end

      def _probe_future_sets(namespace = true)
        labels = add_namespace_labels? ? { namespaced: namespace } : {}
        now = Time.now.to_f
        Sidekiq.redis do |conn|
          Sidekiq::Scheduled::SETS.each do |set|
            # Default to 0; if all jobs are due in the future, there is no "negative" delay.
            delay = 0

            _job, timestamp = conn.zrangebyscore(set, "-inf", now.to_s, limit: [0, 1], withscores: true).first
            delay = now - timestamp if timestamp

            @metrics.add("sidekiq_#{set}_set_processing_delay_seconds", delay, **labels)

            # zcount is O(log(N)) (prob. binary search), so is still quick even with large sets
            @metrics.add("sidekiq_#{set}_set_backlog_count",
                         conn.zcount(set, "-inf", now.to_s), **labels)
          end
        end
      end

      def _probe_stats(namespace = true)
        stats = Sidekiq::Stats.new
        labels = add_namespace_labels? ? { namespaced: namespace } : {}

        @metrics.add("sidekiq_jobs_processed_total", stats.processed, **labels)
        @metrics.add("sidekiq_jobs_failed_total", stats.failed, **labels)
        @metrics.add("sidekiq_jobs_enqueued_size", stats.enqueued, **labels)
        @metrics.add("sidekiq_jobs_scheduled_size", stats.scheduled_size, **labels)
        @metrics.add("sidekiq_jobs_retry_size", stats.retry_size, **labels)
        @metrics.add("sidekiq_jobs_dead_size", stats.dead_size, **labels)

        @metrics.add("sidekiq_default_queue_latency_seconds", stats.default_queue_latency, **labels)
        @metrics.add("sidekiq_processes_size", stats.processes_size, **labels)
        @metrics.add("sidekiq_workers_size", stats.workers_size, **labels)
      end

      def _probe_queues(namespace = true)
        Sidekiq::Queue.all.each do |queue|
          labels = { name: queue.name }
          labels[:namespaced] = namespace if add_namespace_labels?

          @metrics.add("sidekiq_queue_size", queue.size, **labels)
          @metrics.add("sidekiq_queue_latency_seconds", queue.latency, **labels)
          @metrics.add("sidekiq_queue_paused", queue.paused? ? 1 : 0, **labels)
        end
      end

      def _probe_jobs_limit(namespace = true)
        labels = add_namespace_labels? ? { namespaced: namespace } : {}
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
          @metrics.add("sidekiq_enqueued_jobs", count, **labels.merge({ name: class_name }))
        end
      end

      def _probe_retries(namespace = true)
        labels = add_namespace_labels? ? { namespaced: namespace } : {}
        retry_stats = Hash.new(0)

        Sidekiq::RetrySet.new.map do |job|
          retry_stats[job.klass] += 1
        end

        retry_stats.each do |class_name, count|
          @metrics.add("sidekiq_to_be_retried_jobs", count, **labels.merge({ name: class_name }))
        end
      end

      def with_sidekiq(namespaced = true)
        SIDEKIQ_REDIS_LOCK.synchronize {
          Sidekiq.configure_client do |config|
            config.redis = self.class.connection_pool[redis_options(namespaced)]
          end

          return unless connected?

          yield
        }
      end

      def redis_options(namespaced = true)
        options = {
          url: @opts[:redis_url],
          connect_timeout: 1,
          reconnect_attempts: 0
        }

        options[:namespace] = "resque:gitlab" if namespaced
        options[:id] = nil unless redis_enable_client?
        options
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
        @connected = false
      end

      def add_namespace_labels?
        @probe_namespaced && @probe_non_namespaced
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
