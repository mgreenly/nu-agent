# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class QueryDatabase
        def name
          "query_database"
        end

        def description
          "Execute a read-only SELECT query against the agent's history database. Queries are automatically limited to 100 rows (max 1000). Only SELECT queries are allowed - no INSERT, UPDATE, or DELETE."
        end

        def parameters
          {
            sql: {
              type: "string",
              description: "The SQL SELECT query to execute (e.g., 'SELECT * FROM messages WHERE role = \"user\" ORDER BY created_at DESC')",
              required: true
            }
          }
        end

        def execute(arguments:, history:, context:)
          sql = arguments[:sql] || arguments["sql"]

          raise ArgumentError, "sql is required" if sql.nil? || sql.empty?

          begin
            rows = history.execute_readonly_query(sql)

            {
              rows: rows,
              row_count: rows.length,
              query: sql
            }
          rescue ArgumentError => e
            {
              error: e.message,
              query: sql
            }
          rescue => e
            {
              error: "Query execution failed: #{e.message}",
              query: sql
            }
          end
        end
      end
    end
  end
end
