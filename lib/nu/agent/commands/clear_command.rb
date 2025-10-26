# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to clear the screen
      class ClearCommand < BaseCommand
        def execute(_input)
          app.clear_screen
          :continue
        end
      end
    end
  end
end
