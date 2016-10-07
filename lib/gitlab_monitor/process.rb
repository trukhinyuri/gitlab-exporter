module GitLab
  module Monitor
    # A helper class to extract memory info from /proc/<pid>/status
    #
    # It takes a pid
    class ProcessMemory
      def initialize(pid)
        @pid  = pid
        @info = {}

        populate_info
      end

      def [](field)
        @info[field]
      end

      private

      def populate_info
        status = File.read("/proc/#{@pid}/status")

        status.each_line do |line|
          line.strip!

          next unless line.end_with?("kB") # We're only interested in sizes

          match = line.match(/(\w+):\s*(\d+) kB/)
          next unless match

          @info[match[1]] = match[2].to_i * 1024
        end
      rescue Errno::ENOENT
        nil
      end
    end

    # A helper class to stats from /proc/<pid>/stat
    #
    # It takes a pid
    class ProcessStats
      def initialize(pid)
        @pid   = pid
        @stats = nil

        populate_info
      end

      def valid?
        !@stats.nil?
      end

      def age
        Utils.system_uptime - (@stats[21].to_i / Process.clock_getres(:TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID, :hertz))
      end

      private

      def populate_info
        @stats = File.read("/proc/#{@pid}/stat").split(" ")
      rescue Errno::ENOENT
        nil
      end
    end

    # Probes a process for info then writes metrics to a target
    class ProcessProber
      MEMORY_FIELDS = %w(RssFile RssAnon VmRSS VmData).freeze

      def initialize(options, metrics: PrometheusMetrics.new)
        @metrics = metrics
        @name    = options[:name]
        @pids    = if options[:pid_or_pattern] =~ /^\d+$/
                     [options[:pid_or_pattern]]
                   else
                     Utils.pgrep(options[:pid_or_pattern])
                   end
      end

      def probe_memory
        @pids.each do |pid|
          memory = ProcessMemory.new(pid)

          MEMORY_FIELDS.each do |field|
            value = memory[field]
            next unless value

            @metrics.add("process_memory_bytes", value, name: @name.downcase, pid: pid, field: field)
          end
        end

        self
      end

      def probe_age
        @pids.each do |pid|
          stats = ProcessStats.new(pid)
          next unless stats.valid?

          @metrics.add("process_age_seconds", stats.age, name: @name.downcase, pid: pid)
        end

        self
      end

      def write_to(target)
        target.write(@metrics.to_s)
      end
    end
  end
end
