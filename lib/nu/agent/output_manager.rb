# frozen_string_literal: true

module Nu
  module Agent
    class OutputManager
      attr_accessor :debug
      attr_reader :tui

      def initialize(debug: false, tui: nil)
        @debug = debug
        @tui = tui
        @mutex = Mutex.new
        @spinner = Spinner.new
        @waiting = false
        @waiting_message = nil
        @waiting_start_time = nil
      end

      def output(message)
        # Use TUI if available, otherwise stdout
        if @tui && @tui.active
          @tui.write_output(message)
        else
          @mutex.synchronize do
            stop_spinner
            puts message
            restart_spinner
          end
        end
      end

      def debug(message)
        return unless @debug

        # Use TUI if available, otherwise stdout
        if @tui && @tui.active
          @tui.write_debug(message)
        else
          @mutex.synchronize do
            stop_spinner
            puts "\e[90m#{message}\e[0m"
            restart_spinner
          end
        end
      end

      def error(message)
        # Use TUI if available, otherwise stdout
        if @tui && @tui.active
          @tui.write_error(message)
        else
          @mutex.synchronize do
            stop_spinner
            puts "\e[31m#{message}\e[0m"
            restart_spinner
          end
        end
      end

      # Public methods to control spinner (disabled in TUI mode)
      def start_waiting(message = "Thinking...", start_time: nil)
        return if @tui && @tui.active # No spinner in TUI mode

        @mutex.synchronize do
          @waiting = true
          @waiting_message = message
          @waiting_start_time = start_time
          @spinner.start(message, start_time: start_time)
        end
      end

      def stop_waiting
        return if @tui && @tui.active # No spinner in TUI mode

        @mutex.synchronize do
          @waiting = false
          @waiting_message = nil
          @waiting_start_time = nil
          @spinner.stop
        end
      end

      private

      def stop_spinner
        @spinner.stop if @waiting
      end

      def restart_spinner
        @spinner.start(@waiting_message, start_time: @waiting_start_time) if @waiting
      end
    end
  end
end
