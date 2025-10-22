# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class QueryDatabase
        def name
          "query_database"
        end

        def description
          "Execute a SQL query against the agent's history database using a READ-ONLY connection. Only read operations are allowed: SELECT, SHOW, DESCRIBE, EXPLAIN, WITH (CTEs). Write operations (INSERT, UPDATE, DELETE) are blocked. IMPORTANT: Results are hard-capped at 500 rows maximum. Always use LIMIT 100 or less for efficient queries."
        end

        def parameters
          {
            sql: {
              type: "string",
              description: "The read-only SQL query to execute. Do not include a semicolon. MUST include LIMIT clause (100 or less recommended). Results capped at 500 rows maximum. Example: 'SELECT * FROM messages WHERE role = \"user\" ORDER BY created_at DESC LIMIT 50'",
              required: true
            }
          }
        end

        def execute(arguments:, history:, context:)
          sql = arguments[:sql] || arguments["sql"]

          raise ArgumentError, "sql is required" if sql.nil? || sql.empty?

          begin
            rows = history.execute_query(sql)

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
