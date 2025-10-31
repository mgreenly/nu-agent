# frozen_string_literal: true

module Nu
  module Agent
    module Formatters
      class ToolResultFormatter
        def initialize(console:, application:)
          @console = console
          @application = application
        end

        def display(message, batch: nil, thread: nil, start_time: nil, duration: nil, batch_start_time: nil)
          result = message["tool_result"]["result"]
          name = message["tool_result"]["name"]
          verbosity = @application ? @application.verbosity : 0

          display_header(name, batch, thread, start_time, duration, batch_start_time)

          return unless verbosity >= 1

          display_result(result, verbosity)
        end

        private

        def display_header(name, batch, thread, start_time, duration, batch_start_time)
          # Build batch/thread indicator if present
          batch_indicator = if batch && thread
                              " (Batch #{batch}/Thread #{thread})"
                            elsif batch
                              " (Batch #{batch})"
                            else
                              ""
                            end

          # Build timing indicator if present
          timing_indicator = if start_time && duration && batch_start_time
                               format_timing_with_offsets(start_time, duration, batch_start_time)
                             elsif duration
                               format_timing_duration_only(duration)
                             else
                               ""
                             end

          @console.puts("")
          @console.puts("\e[90m[Tool Use Response]#{batch_indicator} #{name}#{timing_indicator}\e[0m")
        end

        def format_timing_with_offsets(start_time, duration, _batch_start_time)
          end_time = start_time + duration
          start_str = format_timestamp(start_time)
          end_str = format_timestamp(end_time)
          duration_ms = (duration * 1000).round
          " [Start: #{start_str}, End: #{end_str}, Duration: #{duration_ms}ms]"
        end

        def format_timestamp(time)
          time.strftime("%H:%M:%S.%3N")
        end

        def format_timing_duration_only(duration)
          formatted_duration = format_duration(duration)
          " [Duration: #{formatted_duration}]"
        end

        def format_duration(duration)
          if duration < 0.001
            "<1ms"
          elsif duration < 1.0
            "#{(duration * 1000).round}ms"
          else
            "#{format('%.2f', duration)}s"
          end
        end

        def display_result(result, verbosity)
          if result.is_a?(Hash)
            format_hash_result(result, verbosity)
          else
            format_simple_result(result, verbosity)
          end
        rescue StandardError => e
          @console.puts("\e[90m  [Error displaying result: #{e.message}]\e[0m")
        end

        def format_hash_result(result, verbosity)
          result.each do |key, value|
            value_str = value.to_s.strip
            if verbosity < 4
              format_truncated_value(key, value_str)
            else
              format_full_value(key, value_str)
            end
          end
        end

        def format_truncated_value(key, value_str)
          if value_str.include?("\n")
            first_line = value_str.lines.first.chomp
            truncated = first_line.length > 30 ? "#{first_line[0...30]}..." : "#{first_line}..."
            @console.puts("\e[90m  #{key}: #{truncated}\e[0m")
          elsif value_str.length > 30
            @console.puts("\e[90m  #{key}: #{value_str[0...30]}...\e[0m")
          else
            @console.puts("\e[90m  #{key}: #{value_str}\e[0m")
          end
        end

        def format_full_value(key, value_str)
          if value_str.include?("\n")
            @console.puts("\e[90m  #{key}:\e[0m")
            value_str.lines.each do |line|
              chomped = line.chomp
              @console.puts("\e[90m    #{chomped}\e[0m") unless chomped.empty?
            end
          else
            @console.puts("\e[90m  #{key}: #{value_str}\e[0m")
          end
        end

        def format_simple_result(result, verbosity)
          result_str = result.to_s
          if verbosity < 4 && result_str.length > 30
            @console.puts("\e[90m  #{result_str[0...30]}...\e[0m")
          else
            @console.puts("\e[90m  #{result_str}\e[0m")
          end
        end
      end
    end
  end
end
