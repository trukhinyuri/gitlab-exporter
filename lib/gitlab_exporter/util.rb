# frozen_string_literal: true

module GitLab
  module Exporter
    # Simple time wrapper that provides a to_i and wraps the execution result
    TrackedResult = Struct.new(:result, :time) do
      def to_i
        time
      end
    end

    # Time tracking object
    #
    # Provides a simple time tracking, and returns back the result plus the tracked time
    # wraped in a TrackedResult struct
    class TimeTracker
      def track
        @start = Time.now.to_f
        result = yield
        TrackedResult.new(result, Time.now.to_f - @start)
      end
    end

    # Helper methods, some stuff was copied from ActiveSupport
    module Utils
      def camel_case_string(str)
        str.gsub(/(?:_|^)([a-z\d]*)/i) { $1.capitalize } # rubocop:disable PerlBackrefs
      end
      module_function :camel_case_string

      def deep_symbolize_hash_keys(hash)
        deep_transform_keys_in_object(hash, &:to_sym)
      end
      module_function :deep_symbolize_hash_keys

      def deep_transform_keys_in_object(object, &block)
        case object
        when Hash
          object.keys.each do |key|
            value = object.delete(key)
            object[yield(key)] = deep_transform_keys_in_object(value, &block)
          end
          object
        when Array
          object.map! { |e| deep_transform_keys_in_object(e, &block) }
        else
          object
        end
      end
      module_function :deep_transform_keys_in_object

      def pgrep(pattern)
        # pgrep will include the PID of the shell, so strip that out
        exec_pgrep(pattern).split("\n").each_with_object([]) do |line, arr|
          pid, name = line.split(" ")
          arr << pid if name != "sh"
        end
      end
      module_function :pgrep

      def exec_pgrep(pattern)
        `pgrep -fl "#{pattern}"`
      end
      module_function :exec_pgrep

      def system_uptime
        File.read("/proc/uptime").split(" ")[0].to_f
      end
      module_function :system_uptime

      def wrap_in_array(object)
        if object.nil?
          []
        elsif object.respond_to?(:to_ary)
          object.to_ary || [object]
        else
          [object]
        end
      end
      module_function :wrap_in_array
    end
  end
end
