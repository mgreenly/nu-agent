# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to display session information
      class InfoCommand < BaseCommand
        def execute(_input)
          app.print_info
          :continue
        end
      end
    end
  end
end
