# frozen_string_literal: true

module Nu
  module Agent
    # Manages exchange migration from existing messages
    class ExchangeMigrator
      def initialize(connection, conversation_repo, message_repo, exchange_repo)
        @connection = connection
        @conversation_repo = conversation_repo
        @message_repo = message_repo
        @exchange_repo = exchange_repo
      end

      def migrate_exchanges
        stats = {
          conversations: 0,
          exchanges_created: 0,
          messages_updated: 0
        }

        conversations = @conversation_repo.all_conversations

        conversations.each do |conv|
          conv_stats = process_conversation(conv["id"])
          stats[:exchanges_created] += conv_stats[:exchanges_created]
          stats[:messages_updated] += conv_stats[:messages_updated]
          stats[:conversations] += 1
        end

        stats
      end

      private

      def process_conversation(conv_id)
        stats = { exchanges_created: 0, messages_updated: 0 }
        messages = fetch_conversation_messages(conv_id)

        return stats if messages.empty?

        process_messages_into_exchanges(conv_id, messages, stats)

        stats
      end

      def process_messages_into_exchanges(conv_id, messages, stats)
        current_exchange_id = nil
        exchange_messages = []

        messages.each do |msg|
          # Start new exchange on user messages (excluding spell_checker)
          if msg["role"] == "user" && msg["actor"] != "spell_checker"
            # Finalize previous exchange if exists
            finalize_current_exchange(current_exchange_id, exchange_messages, stats) if current_exchange_id

            # Create new exchange
            current_exchange_id = @exchange_repo.create_exchange(
              conversation_id: conv_id,
              user_message: msg["content"] || ""
            )
            stats[:exchanges_created] += 1
            exchange_messages = [msg]
          elsif current_exchange_id
            # Add to current exchange (if one exists)
            exchange_messages << msg
          end
        end

        # Finalize last exchange
        finalize_current_exchange(current_exchange_id, exchange_messages, stats) if current_exchange_id
      end

      def finalize_current_exchange(exchange_id, messages, stats)
        return if messages.empty?

        finalize_exchange(exchange_id, messages)
        stats[:messages_updated] += messages.length
      end

      def fetch_conversation_messages(conv_id)
        # Get all messages for this conversation (not just current session)
        result = @connection.query(<<~SQL)
          SELECT id, actor, role, content, model, tokens_input, tokens_output,
                 tool_calls, tool_call_id, tool_result, error, created_at, redacted, spend
          FROM messages
          WHERE conversation_id = #{conv_id}
          ORDER BY id ASC
        SQL

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
            "spend" => row[13]
          }
        end
      end

      def finalize_exchange(exchange_id, messages)
        # Calculate metrics from messages
        metrics = calculate_exchange_metrics(messages)

        # Find final assistant message
        assistant_msg = find_final_assistant_message(messages)

        # Get timestamps from messages (they're already Time objects)
        started_at = messages.first["created_at"]
        completed_at = messages.last["created_at"]

        # Convert to Time if they're strings
        started_at = Time.parse(started_at) if started_at.is_a?(String)
        completed_at = Time.parse(completed_at) if completed_at.is_a?(String)

        # Build update clauses
        set_clauses = build_exchange_updates(
          metrics,
          assistant_msg,
          started_at,
          completed_at,
          messages.length
        )

        # Update exchange with completion info
        @connection.query(<<~SQL)
          UPDATE exchanges
          SET #{set_clauses.join(', ')}
          WHERE id = #{exchange_id}
        SQL

        # Update all messages with this exchange_id
        update_message_exchange_ids(messages, exchange_id)
      end

      def calculate_exchange_metrics(messages)
        {
          tokens_input: messages.map { |m| m["tokens_input"] || 0 }.max || 0,
          tokens_output: messages.sum { |m| m["tokens_output"] || 0 },
          spend: messages.sum { |m| m["spend"] || 0.0 },
          tool_call_count: messages.count { |m| m["tool_calls"] && !m["tool_calls"].empty? }
        }
      end

      def find_final_assistant_message(messages)
        messages.reverse.find do |m|
          m["role"] == "assistant" && m["content"] && !m["content"].empty? && !m["tool_calls"]
        end
      end

      def build_exchange_updates(metrics, assistant_msg, started_at, completed_at, message_count)
        set_clauses = [
          "status = 'completed'",
          "completed_at = '#{completed_at.strftime('%Y-%m-%d %H:%M:%S.%6N')}'",
          "started_at = '#{started_at.strftime('%Y-%m-%d %H:%M:%S.%6N')}'",
          "tokens_input = #{metrics[:tokens_input]}",
          "tokens_output = #{metrics[:tokens_output]}",
          "spend = #{metrics[:spend]}",
          "message_count = #{message_count}",
          "tool_call_count = #{metrics[:tool_call_count]}"
        ]

        if assistant_msg && assistant_msg["content"]
          set_clauses << "assistant_message = '#{escape_sql(assistant_msg['content'])}'"
        end

        set_clauses
      end

      def update_message_exchange_ids(messages, exchange_id)
        messages.each do |msg|
          @message_repo.update_message_exchange_id(message_id: msg["id"], exchange_id: exchange_id)
        end
      end

      def escape_sql(string)
        string.to_s.gsub("'", "''")
      end
    end
  end
end
