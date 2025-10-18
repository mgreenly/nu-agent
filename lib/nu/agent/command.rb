# frozen_string_literal: true

module Nu
  module Agent
    class Command
      def initialize(input, llm)
        @input = input
        @llm = llm
      end

      def execute
        command = @input.downcase

        case command
        when '/exit'
          :exit
        when '/reset'
          @llm.token_tracker.reset
          puts "Token count reset to zero"
          :continue
        when '/help'
          print_help
          :continue
        else
          puts "Unknown command: #{@input}"
          :continue
        end
      end

      private

      def print_help
        puts "\nAvailable commands:"
        puts "  /exit   - Exit the REPL"
        puts "  /help   - Show this help message"
        puts "  /reset  - Reset token count to zero"
      end
    end
  end
end
