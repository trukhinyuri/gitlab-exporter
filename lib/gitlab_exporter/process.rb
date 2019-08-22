# frozen_string_literal: true

require_relative "memstats"

module GitLab
  module Exporter
    # A helper class to extract memory info from /proc/<pid>/status
    #

    # A helper class to stats from /proc/<pid>/stat
    #
    # See: man 5 proc
    #
    # It takes a pid
    class ProcessStats
      def initialize(pid)
        @pid = pid
        @user_hertz = retrieve_user_hertz
        @stats = populate_info
      end

      def valid?
        !@stats.nil?
      end

      def cpu_time
        (@stats[14].to_i + @stats[15].to_i) / @user_hertz
      end

      def start_time
        @stats[22].to_i / @user_hertz
      end

      def vsize
        # Virtual memory size in bytes.
        @stats[23].to_i
      end

      def rss
        # Resident Set Size: number of pages the process has in real memory.
        @stats[24].to_i * 4096
      end

      private

      def populate_info
        # Pad the array by one element to make field numbers match the man page.
        [""].concat(File.read("/proc/#{@pid}/stat").split(" "))
      rescue Errno::ENOENT
        nil
      end

      def retrieve_user_hertz
        Process.clock_getres(:TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID, :hertz)
      rescue Errno::EINVAL
        100.0
      end
    end

    # Probes a process for info then writes metrics to a target
    class ProcessProber
      def initialize(options, metrics: PrometheusMetrics.new)
        @metrics = metrics
        @name    = options[:name]
        @pids    = if options[:pid_or_pattern] =~ /^\d+$/
                     [options[:pid_or_pattern]]
                   else
                     Utils.pgrep(options[:pid_or_pattern])
                   end
        @use_quantiles = options.fetch(:quantiles, false)
      end

      def probe_stat
        @pids.each do |pid|
          stats = ProcessStats.new(pid)
          next unless stats.valid?

          labels = { name: @name.downcase }
          labels[:pid] = pid unless @use_quantiles

          @metrics.add("process_cpu_seconds_total", stats.cpu_time, @use_quantiles, **labels)
          @metrics.add("process_resident_memory_bytes", stats.rss, @use_quantiles, **labels)
          @metrics.add("process_virtual_memory_bytes", stats.vsize, @use_quantiles, **labels)
          @metrics.add("process_start_time_seconds", stats.start_time, @use_quantiles, **labels)
        end

        self
      end

      def probe_count
        @metrics.add("process_count", @pids.count, name: @name.downcase)

        self
      end

      def probe_smaps
        @pids.each do |pid|
          stats = ::GitLab::Exporter::MemStats::Aggregator.new(pid)

          next unless stats.valid?

          labels = { name: @name.downcase }
          labels[:pid] = pid unless @use_quantiles

          ::GitLab::Exporter::MemStats::Mapping::FIELDS.each do |field|
            value = stats.totals[field]

            if value >= 0
              @metrics.add("process_smaps_#{field}_bytes", value * 1024, @use_quantiles, **labels)
            end
          end
        end

        self
      end

      def write_to(target)
        target.write(@metrics.to_s)
      end
    end
  end
end
