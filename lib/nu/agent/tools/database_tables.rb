# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DatabaseTables
        def name
          "database_tables"
        end

        def description
          "PREFERRED tool for listing database tables. " \
            "Use this to discover what conversation data is available to query. " \
            "Returns table names that can be used with database_schema to see structure or database_query to retrieve data."
        end

        def parameters
          {}
        end

        def execute(arguments:, history:, context:)
          # Debug output
          application = context["application"]
          application.console.puts("\e[90m[database_tables] listing tables\e[0m") if application&.debug

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
