# frozen_string_literal: true

module Nu
  module Agent
    class OutputManager
      attr_accessor :debug

      def initialize(debug: false)
        @debug = debug
        @mutex = Mutex.new
        @spinner = nil  # Future: spinner integration
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

      private

      def stop_spinner
        # Future: @spinner&.stop
      end

      def restart_spinner
        # Future: @spinner&.start if @waiting
      end
    end
  end
end
