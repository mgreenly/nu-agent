# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to scan and fix database corruption
      class FixCommand < BaseCommand
        def execute(_input)
          app.run_fix
          :continue
        end
      end
    end
  end
end
