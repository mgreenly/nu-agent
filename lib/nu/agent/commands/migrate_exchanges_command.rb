# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to migrate existing messages into exchanges
      class MigrateExchangesCommand < BaseCommand
        def execute(_input)
          app.run_migrate_exchanges
          :continue
        end
      end
    end
  end
end
