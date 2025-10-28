# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DatabaseSchema
        PARAMETERS = {
          table_name: {
            type: "string",
            description: "The name of the table to describe (e.g., 'messages', 'conversations', 'appconfig')",
            required: true
          }
        }.freeze

        def name
          "database_schema"
        end

        def description
          "PREFERRED tool for viewing table schemas. " \
            "Shows column names, types, and constraints for a specific table in the agent's history database. " \
            "Use database_tables first to see available tables, " \
            "then use this tool to understand table structure before querying with database_query."
        end

        def parameters
          PARAMETERS
        end

        def execute(arguments:, history:, context:)
          table_name = arguments[:table_name] || arguments["table_name"]

          if table_name.nil? || table_name.empty?
            return {
              error: "table_name is required"
            }
          end

          # Debug output
          context["application"]

          columns = history.describe_table(table_name)

          {
            table_name: table_name,
            columns: columns,
            column_count: columns.length
          }
        rescue StandardError => e
          {
            error: e.message,
            table_name: table_name
          }
        end
      end
    end
  end
end
