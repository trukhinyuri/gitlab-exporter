require "sidekiq/api"

module GitLab
  module Monitor
    # A prober for Sidekiq queues
    #
    # It takes the Redis URL Sidekiq is connected to
    class SidekiqProber
      def initialize(opts, metrics: PrometheusMetrics.new)
        @opts    = opts
        @metrics = metrics

        Sidekiq.configure_client { |config|
          config.redis = { url: opts[:redis_url], namespace: "resque:gitlab" }
        }
      end

      def probe_queues
        return self unless connected?

        job_stats = Hash.new(0)

        Sidekiq::Queue.all.each do |queue|
          @metrics.add("sidekiq_queue_size", queue.size, name: queue.name)
          @metrics.add("sidekiq_queue_latency", queue.latency, name: queue.name)

          queue.each { |job| job_stats[job.klass] += 1 }
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
    end
  end
end
