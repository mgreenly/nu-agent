# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to exit the REPL
      class ExitCommand < BaseCommand
        def execute(_input)
          :exit
        end
      end
    end
  end
end
