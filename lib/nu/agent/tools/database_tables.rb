# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DatabaseTables
        PARAMETERS = {}.freeze

        def name
          "database_tables"
        end

        def description
          "PREFERRED tool for listing database tables. " \
            "Use this to discover what conversation data is available to query. " \
            "Returns table names that can be used with database_schema to see structure " \
            "or database_query to retrieve data."
        end

        def parameters
          PARAMETERS
        end

        def execute(history:, context:, **)
          # Debug output
          context["application"]

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
