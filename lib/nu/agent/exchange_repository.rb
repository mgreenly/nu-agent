# frozen_string_literal: true

module Nu
  module Agent
    # Manages exchange CRUD operations
    class ExchangeRepository
      def initialize(connection)
        @connection = connection
      end

      def create_exchange(conversation_id:, user_message:)
        # Get the next exchange number for this conversation
        result = @connection.query(<<~SQL)
          SELECT COALESCE(MAX(exchange_number), 0) + 1 as next_number
          FROM exchanges
          WHERE conversation_id = #{conversation_id}
        SQL
        exchange_number = result.to_a.first.first

        # Create the exchange
        result = @connection.query(<<~SQL)
          INSERT INTO exchanges (
            conversation_id, exchange_number, started_at, status, user_message
          ) VALUES (
            #{conversation_id}, #{exchange_number}, CURRENT_TIMESTAMP, 'in_progress', '#{escape_sql(user_message)}'
          )
          RETURNING id
        SQL
        result.to_a.first.first
      end

      def update_exchange(exchange_id:, updates: {})
        set_clauses = []

        updates.each do |key, value|
          case key.to_s
          when "status", "summary", "summary_model", "error", "assistant_message"
            set_clauses << "#{key} = '#{escape_sql(value)}'"
          when "completed_at"
            set_clauses << if value.is_a?(Time)
                             "#{key} = '#{value.strftime('%Y-%m-%d %H:%M:%S.%6N')}'"
                           else
                             "#{key} = CURRENT_TIMESTAMP"
                           end
          when "tokens_input", "tokens_output", "spend", "message_count", "tool_call_count"
            set_clauses << "#{key} = #{value || 'NULL'}"
          end
        end

        return if set_clauses.empty?

        @connection.query(<<~SQL)
          UPDATE exchanges
          SET #{set_clauses.join(', ')}
          WHERE id = #{exchange_id}
        SQL
      end

      def complete_exchange(exchange_id:, summary: nil, assistant_message: nil, metrics: {})
        set_clauses = ["status = 'completed'", "completed_at = CURRENT_TIMESTAMP"]

        set_clauses << "summary = '#{escape_sql(summary)}'" if summary

        set_clauses << "assistant_message = '#{escape_sql(assistant_message)}'" if assistant_message

        # Add metrics
        metrics.each do |key, value|
          case key.to_s
          when "tokens_input", "tokens_output", "spend", "message_count", "tool_call_count"
            set_clauses << "#{key} = #{value || 'NULL'}"
          end
        end

        @connection.query(<<~SQL)
          UPDATE exchanges
          SET #{set_clauses.join(', ')}
          WHERE id = #{exchange_id}
        SQL
      end

      def get_conversation_exchanges(conversation_id:)
        result = @connection.query(<<~SQL)
          SELECT id, exchange_number, started_at, completed_at, status,
                 user_message, assistant_message, summary,
                 tokens_input, tokens_output, spend,
                 message_count, tool_call_count
          FROM exchanges
          WHERE conversation_id = #{conversation_id}
          ORDER BY exchange_number ASC
        SQL

        result.map { |row| row_to_exchange_hash(row) }
      end

      def row_to_exchange_hash(row)
        {
          "id" => row[0],
          "exchange_number" => row[1],
          "started_at" => row[2],
          "completed_at" => row[3],
          "status" => row[4],
          "user_message" => row[5],
          "assistant_message" => row[6],
          "summary" => row[7],
          "tokens_input" => row[8],
          "tokens_output" => row[9],
          "spend" => row[10],
          "message_count" => row[11],
          "tool_call_count" => row[12]
        }
      end

      private

      def escape_sql(string)
        string.to_s.gsub("'", "''")
      end
    end
  end
end
