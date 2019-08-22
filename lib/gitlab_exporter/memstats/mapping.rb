# frozen_string_literal: true

module GitLab
  module Exporter
    module MemStats
      # Parses one entry in /proc/[pid]/smaps. For example:
      #
      # 00400000-00401000 r-xp 00000000 08:01 541055                             /opt/gitlab/embedded/bin/ruby
      # Size:                  4 kB
      # Rss:                   4 kB
      # Pss:                   0 kB
      # Shared_Clean:          4 kB
      # Shared_Dirty:          0 kB
      # Private_Clean:         0 kB
      # Private_Dirty:         0 kB
      # Referenced:            4 kB
      # Anonymous:             0 kB
      # AnonHugePages:         0 kB
      # Shared_Hugetlb:        0 kB
      # Private_Hugetlb:       0 kB
      # Swap:                  0 kB
      # SwapPss:               0 kB
      # KernelPageSize:        4 kB
      # MMUPageSize:           4 kB
      # Locked:                0 kB
      # VmFlags: rd ex mr mw me dw sd
      class Mapping
        FIELDS = %w(size rss shared_clean shared_dirty private_clean private_dirty swap pss).freeze

        attr_reader :address_start
        attr_reader :address_end
        attr_reader :perms
        attr_reader :offset
        attr_reader :device_major
        attr_reader :device_minor
        attr_reader :inode
        attr_reader :region

        attr_accessor :size
        attr_accessor :rss
        attr_accessor :shared_clean
        attr_accessor :shared_dirty
        attr_accessor :private_dirty
        attr_accessor :private_clean
        attr_accessor :swap
        attr_accessor :pss

        def initialize(lines)
          FIELDS.each do |field|
            send("#{field}=", 0)
          end

          parse_first_line(lines.shift)

          lines.each do |l|
            parse_field_line(l)
          end
        end

        def parse_first_line(line)
          line.strip!

          parts = line.split
          @address_start, @address_end = parts[0].split("-")
          @perms = parts[1]
          @offset = parts[2]
          @device_major, @device_minor = parts[3].split(":")
          @inode = parts[4]
          @region = parts[5] || "anonymous"
        end

        def parse_field_line(line)
          line.strip!

          parts = line.split

          return unless parts

          parts[0].downcase!
          parts[0].sub!(":", "")
          field = parts[0]

          return unless respond_to? "#{field}="

          value = Float(parts[1]).to_i
          send("#{field}=", value)
        end
      end
    end
  end
end
