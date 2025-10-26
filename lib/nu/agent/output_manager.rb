# frozen_string_literal: true

module Nu
  module Agent
    class OutputManager
      attr_accessor :debug, :verbosity
      attr_reader :tui

      def initialize(debug: false, tui:, verbosity: 0)
        @debug = debug
        @verbosity = verbosity
        @tui = tui
      end

      def flush_buffer(buffer)
        # Output all buffered lines atomically
        return if buffer.empty?

        # Filter out debug lines if debug mode is disabled
        filtered_lines = buffer.lines.reject do |line|
          line[:type] == :debug && (!@debug || @verbosity < 0)
        end

        # Don't flush if all lines were filtered out
        return if filtered_lines.empty?

        # Additional check: if buffer contains ONLY empty/whitespace lines, skip it
        # This prevents buffers full of blank lines from creating extra spacing
        all_empty = filtered_lines.all? { |line| line[:text].to_s.strip.empty? }
        return if all_empty

        # Write all lines atomically to TUI
        @tui.write_buffer(filtered_lines)
      end

      # Spinner methods are no-ops (TUI doesn't use spinner)
      def start_waiting(message = "Thinking...", start_time: nil)
        # No-op in TUI mode
      end

      def stop_waiting
        # No-op in TUI mode
      end
    end
  end
end
