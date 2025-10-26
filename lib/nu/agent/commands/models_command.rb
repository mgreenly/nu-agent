# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to list available models
      class ModelsCommand < BaseCommand
        def execute(_input)
          app.print_models
          :continue
        end
      end
    end
  end
end
