# frozen_string_literal: true

module Nu
  module Agent
    # Manages message CRUD operations
    class MessageRepository
      def initialize(connection)
        @connection = connection
      end

      def add_message(conversation_id:, actor:, role:, content:, **attributes)
        attrs = attribute_defaults_for(attributes)
        values = build_insert_values(conversation_id, actor, role, content, attrs)

        @connection.query(<<~SQL)
          INSERT INTO messages (
            conversation_id, actor, role, content, model,
            include_in_context, tokens_input, tokens_output, spend,
            tool_calls, tool_call_id, tool_result, error, redacted, exchange_id, created_at
          ) VALUES (#{values})
        SQL
      end

      def attribute_defaults_for(attributes)
        {
          model: nil,
          include_in_context: true,
          tokens_input: nil,
          tokens_output: nil,
          spend: nil,
          tool_calls: nil,
          tool_call_id: nil,
          tool_result: nil,
          error: nil,
          redacted: false,
          exchange_id: nil
        }.merge(attributes)
      end

      def build_insert_values(conversation_id, actor, role, content, attrs)
        [
          conversation_id,
          "'#{escape_sql(actor)}'",
          "'#{escape_sql(role)}'",
          "'#{escape_sql(content || '')}'",
          string_or_null(attrs[:model]),
          attrs[:include_in_context],
          attrs[:tokens_input] || "NULL",
          attrs[:tokens_output] || "NULL",
          attrs[:spend] || "NULL",
          json_value(attrs[:tool_calls]),
          string_or_null(attrs[:tool_call_id]),
          json_value(attrs[:tool_result]),
          json_value(attrs[:error]),
          attrs[:redacted],
          attrs[:exchange_id] || "NULL",
          "CURRENT_TIMESTAMP"
        ].join(", ")
      end

      def json_value(value)
        value ? "'#{escape_sql(JSON.generate(value))}'" : "NULL"
      end

      def string_or_null(value)
        value ? "'#{escape_sql(value)}'" : "NULL"
      end

      def messages(conversation_id:, include_in_context_only: true, since: nil)
        conditions = []
        conditions << "include_in_context = true" if include_in_context_only
        conditions << "created_at >= '#{since.strftime('%Y-%m-%d %H:%M:%S.%6N')}'" if since

        where_clause = conditions.empty? ? "" : "AND #{conditions.join(' AND ')}"

        result = @connection.query(<<~SQL)
          SELECT id, actor, role, content, model, tokens_input, tokens_output,
                 tool_calls, tool_call_id, tool_result, error, created_at, redacted, exchange_id
          FROM messages
          WHERE conversation_id = #{conversation_id} #{where_clause}
          ORDER BY id ASC
        SQL

        map_message_rows(result)
      end

      def messages_since(conversation_id:, message_id:)
        result = @connection.query(<<~SQL)
          SELECT id, actor, role, content, model, tokens_input, tokens_output,
                 tool_calls, tool_call_id, tool_result, error, created_at, redacted, exchange_id
          FROM messages
          WHERE conversation_id = #{conversation_id} AND id > #{message_id}
          ORDER BY id ASC
        SQL

        map_message_rows(result)
      end

      def session_tokens(conversation_id:, since:)
        result = @connection.query(<<~SQL)
          SELECT
            COALESCE(MAX(tokens_input), 0) as total_input,
            COALESCE(SUM(tokens_output), 0) as total_output,
            COALESCE(SUM(spend), 0.0) as total_spend
          FROM messages
          WHERE conversation_id = #{conversation_id}
            AND created_at >= '#{since.strftime('%Y-%m-%d %H:%M:%S.%6N')}'
        SQL

        row = result.to_a.first
        {
          "input" => row[0],
          "output" => row[1],
          "total" => row[0] + row[1],
          "spend" => row[2]
        }
      end

      def current_context_size(conversation_id:, since:, model:)
        result = @connection.query(<<~SQL)
          SELECT tokens_input
          FROM messages
          WHERE conversation_id = #{conversation_id}
            AND created_at >= '#{since.strftime('%Y-%m-%d %H:%M:%S.%6N')}'
            AND model = '#{escape_sql(model)}'
            AND tokens_input IS NOT NULL
          ORDER BY created_at DESC
          LIMIT 1
        SQL

        row = result.to_a.first
        row ? row[0] : 0
      end

      def get_message_by_id(message_id, conversation_id:)
        result = @connection.query(<<~SQL)
          SELECT id, actor, role, content, model, tokens_input, tokens_output,
                 tool_calls, tool_call_id, tool_result, error, created_at
          FROM messages
          WHERE id = #{message_id} AND conversation_id = #{conversation_id}
          LIMIT 1
        SQL

        rows = result.to_a
        return nil if rows.empty?

        map_message_row(rows.first)
      end

      def update_message_exchange_id(message_id:, exchange_id:)
        @connection.query(<<~SQL)
          UPDATE messages
          SET exchange_id = #{exchange_id}
          WHERE id = #{message_id}
        SQL
      end

      def get_exchange_messages(exchange_id:)
        result = @connection.query(<<~SQL)
          SELECT id, actor, role, content, model, tokens_input, tokens_output,
                 tool_calls, tool_call_id, tool_result, error, created_at, redacted, exchange_id
          FROM messages
          WHERE exchange_id = #{exchange_id}
          ORDER BY id ASC
        SQL

        map_message_rows(result)
      end

      private

      def map_message_rows(result)
        result.map do |row|
          {
            "id" => row[0],
            "actor" => row[1],
            "role" => row[2],
            "content" => row[3],
            "model" => row[4],
            "tokens_input" => row[5],
            "tokens_output" => row[6],
            "tool_calls" => row[7] ? JSON.parse(row[7]) : nil,
            "tool_call_id" => row[8],
            "tool_result" => row[9] ? JSON.parse(row[9]) : nil,
            "error" => row[10] ? JSON.parse(row[10]) : nil,
            "created_at" => row[11],
            "redacted" => row[12],
            "exchange_id" => row[13]
          }
        end
      end

      def map_message_row(row)
        {
          "id" => row[0],
          "actor" => row[1],
          "role" => row[2],
          "content" => row[3],
          "model" => row[4],
          "tokens_input" => row[5],
          "tokens_output" => row[6],
          "tool_calls" => row[7] ? JSON.parse(row[7]) : nil,
          "tool_call_id" => row[8],
          "tool_result" => row[9] ? JSON.parse(row[9]) : nil,
          "error" => row[10] ? JSON.parse(row[10]) : nil,
          "created_at" => row[11]
        }
      end

      def escape_sql(string)
        string.to_s.gsub("'", "''")
      end
    end
  end
end
