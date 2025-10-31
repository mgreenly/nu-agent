# frozen_string_literal: true

require_relative "../subsystem_debugger"

module Nu
  module Agent
    module Formatters
      class ToolCallFormatter
        def initialize(console:, application:)
          @console = console
          @application = application
        end

        def display(tool_call, index: nil, total: nil, batch: nil, thread: nil)
          # Level 0: No tool debug output
          return unless should_output?(1)

          display_header(tool_call["name"], index, total, batch, thread)

          # Level 1: Show tool name only, no arguments
          return unless should_output?(2)

          # Level 2+: Show arguments (truncated or full depending on level)
          display_arguments(tool_call["arguments"])
        end

        private

        def should_output?(level)
          return false unless @application

          SubsystemDebugger.should_output?(@application, "tools", level)
        end

        def display_header(name, index, total, batch, thread)
          # Build batch/thread indicator if present
          batch_indicator = if batch && thread
                              " (Batch #{batch}/Thread #{thread})"
                            elsif batch
                              " (Batch #{batch})"
                            else
                              ""
                            end

          # Build count indicator if present
          count_indicator = index && total && total > 1 ? " (#{index}/#{total})" : ""

          @console.puts("")
          @console.puts("\e[90m[Tool Call Request]#{batch_indicator} #{name}#{count_indicator}\e[0m")
        end

        def display_arguments(arguments)
          return unless arguments && !arguments.empty?

          begin
            arguments.each do |key, value|
              format_argument(key, value.to_s.strip)
            end
          rescue StandardError => e
            @console.puts("\e[90m  [Error displaying arguments: #{e.message}]\e[0m")
          end
        end

        def format_argument(key, value_str)
          # Level 3+: Show full arguments without truncation
          if should_output?(3)
            if value_str.include?("\n")
              format_multiline_argument(key, value_str)
            else
              @console.puts("\e[90m  #{key}: #{value_str}\e[0m")
            end
          else
            # Level 2: Show truncated arguments
            format_truncated_argument(key, value_str)
          end
        end

        def format_truncated_argument(key, value_str)
          if value_str.length > 30
            @console.puts("\e[90m  #{key}: #{value_str[0...30]}...\e[0m")
          else
            @console.puts("\e[90m  #{key}: #{value_str}\e[0m")
          end
        end

        def format_multiline_argument(key, value_str)
          @console.puts("\e[90m  #{key}:\e[0m")
          value_str.lines.each do |line|
            chomped = line.chomp
            @console.puts("\e[90m    #{chomped}\e[0m") unless chomped.empty?
          end
        end
      end
    end
  end
end
