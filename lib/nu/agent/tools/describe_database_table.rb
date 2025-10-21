# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DescribeDatabaseTable
        def name
          "describe_database_table"
        end

        def description
          "Get the schema/structure of a specific table in the agent's history database. Shows column names, types, and constraints."
        end

        def parameters
          {
            table_name: {
              type: "string",
              description: "The name of the table to describe (e.g., 'messages', 'conversations', 'appconfig')",
              required: true
            }
          }
        end

        def execute(arguments:, history:, context:)
          table_name = arguments[:table_name] || arguments["table_name"]

          raise ArgumentError, "table_name is required" if table_name.nil? || table_name.empty?

          columns = history.describe_table(table_name)

          {
            table_name: table_name,
            columns: columns,
            column_count: columns.length
          }
        end
      end
    end
  end
end
