# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class ListDatabaseTables
        def name
          "list_database_tables"
        end

        def description
          "List all tables in the agent's history database. Use this to discover what data is available to query."
        end

        def parameters
          {}
        end

        def execute(arguments:, history:, context:)
          tables = history.list_tables

          {
            tables: tables,
            count: tables.length
          }
        end
      end
    end
  end
end
