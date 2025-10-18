# frozen_string_literal: true

module Nu
  module Agent
    class Command
      def initialize(input)
        @input = input
      end

      def execute
        command = @input.downcase

        case command
        when '/exit'
          true  # Signal to exit
        else
          puts "Unknown command: #{@input}"
          false
        end
      end
    end
  end
end
