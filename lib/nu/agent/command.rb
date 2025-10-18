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
        else
          puts "Unknown command: #{@input}"
          :continue
        end
      end
    end
  end
end
