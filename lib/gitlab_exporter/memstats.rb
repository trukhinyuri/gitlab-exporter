# frozen_string_literal: true

require_relative "memstats/mapping"

# Ported from https://github.com/discourse/discourse/blob/master/script/memstats.rb
#
# Aggregate Print useful information from /proc/[pid]/smaps
#
# pss  - Roughly the amount of memory that is "really" being used by the pid
# swap - Amount of swap this process is currently using
#
# Reference:
#  http://www.mjmwired.net/kernel/Documentation/filesystems/proc.txt#361
#
# Example:
#   # ./memstats.rb 4386
#   Process:             4386
#   Command Line:        /usr/bin/mongod -f /etc/mongo/mongod.conf
#   Memory Summary:
#     private_clean             107,132 kB
#     private_dirty           2,020,676 kB
#     pss                     2,127,860 kB
#     rss                     2,128,536 kB
#     shared_clean                  728 kB
#     shared_dirty                    0 kB
#     size                  149,281,668 kB
#     swap                    1,719,792 kB
module GitLab
  module Exporter
    module MemStats
      # Aggregates all metrics for a single PID in /proc/<pid>/smaps
      class Aggregator
        attr_accessor :pid, :totals

        def initialize(pid)
          @pid = pid
          @totals = Hash.new(0)
          @mappings = []
          @valid = true

          populate_info
        end

        def valid?
          @valid
        end

        private

        attr_accessor :mappings

        def consume_mapping(map_lines, totals)
          m = Mapping.new(map_lines)

          Mapping::FIELDS.each do |field|
            totals[field] += m.send(field)
          end

          m
        end

        def create_memstats_not_available(totals)
          Mapping::FIELDS.each do |field|
            totals[field] += Float::NAN
          end
        end

        def populate_info # rubocop:disable Metrics/MethodLength
          File.open("/proc/#{@pid}/smaps") do |smaps|
            map_lines = []

            loop do
              break if smaps.eof?

              line = smaps.readline.strip

              case line
              when /\w+:\s+/
                map_lines << line
              when /[0-9a-f]+:[0-9a-f]+\s+/
                mappings << consume_mapping(map_lines, totals) if map_lines.size.positive?

                map_lines.clear
                map_lines << line
              else
                break
              end
            end
          end
        rescue => e
          puts "Error: #{e}"
          @valid = false
          create_memstats_not_available(totals)
        end
      end
    end
  end
end
