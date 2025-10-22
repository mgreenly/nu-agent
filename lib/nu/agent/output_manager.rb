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
      def start_waiting(message = "Thinking...")
        @mutex.synchronize do
          @waiting = true
          @spinner.start(message)
        end
      end

      def stop_waiting
        @mutex.synchronize do
          @waiting = false
          @spinner.stop
        end
      end

      private

      def stop_spinner
        @spinner.stop if @waiting
      end

      def restart_spinner
        @spinner.start if @waiting
      end
    end
  end
end
