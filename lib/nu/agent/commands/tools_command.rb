# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to list available tools
      class ToolsCommand < BaseCommand
        def execute(_input)
          app.print_tools
          :continue
        end
      end
    end
  end
end
