# frozen_string_literal: true

module Nu
  module Agent
    class OutputManager
      attr_accessor :debug

      def initialize(debug: false)
        @debug = debug
        @mutex = Mutex.new
        @spinner = Spinner.new
        @waiting = false
        @waiting_message = nil
        @waiting_start_time = nil
      end

      def output(message)
        @mutex.synchronize do
          stop_spinner
          puts message
          restart_spinner
        end
      end

      def debug(message)
        return unless @debug

        @mutex.synchronize do
          stop_spinner
          puts "\e[90m#{message}\e[0m"
          restart_spinner
        end
      end

      def error(message)
        @mutex.synchronize do
          stop_spinner
          puts "\e[31m#{message}\e[0m"
          restart_spinner
        end
      end

      # Public methods to control spinner
      def start_waiting(message = "Thinking...", start_time: nil)
        @mutex.synchronize do
          @waiting = true
          @waiting_message = message
          @waiting_start_time = start_time
          @spinner.start(message, start_time: start_time)
        end
      end

      def stop_waiting
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
