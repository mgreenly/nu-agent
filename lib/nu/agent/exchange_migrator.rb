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
          conv_id = conv["id"]

          # Get all messages for this conversation (not just current session)
          result = @connection.query(<<~SQL)
            SELECT id, actor, role, content, model, tokens_input, tokens_output,
                   tool_calls, tool_call_id, tool_result, error, created_at, redacted, spend
            FROM messages
            WHERE conversation_id = #{conv_id}
            ORDER BY id ASC
          SQL

          messages = result.map do |row|
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

          next if messages.empty?

          current_exchange_id = nil
          exchange_messages = []

          messages.each do |msg|
            # Start new exchange on user messages (excluding spell_checker)
            if msg["role"] == "user" && msg["actor"] != "spell_checker"
              # Finalize previous exchange if exists
              if current_exchange_id && !exchange_messages.empty?
                finalize_exchange(current_exchange_id, exchange_messages)
                stats[:messages_updated] += exchange_messages.length
              end

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
          if current_exchange_id && !exchange_messages.empty?
            finalize_exchange(current_exchange_id, exchange_messages)
            stats[:messages_updated] += exchange_messages.length
          end

          stats[:conversations] += 1
        end

        stats
      end

      private

      def finalize_exchange(exchange_id, messages)
        # Calculate metrics from messages
        tokens_input = messages.map { |m| m["tokens_input"] || 0 }.max || 0
        tokens_output = messages.sum { |m| m["tokens_output"] || 0 }
        spend = messages.sum { |m| m["spend"] || 0.0 }
        tool_call_count = messages.count { |m| m["tool_calls"] && !m["tool_calls"].empty? }

        # Find final assistant message (last assistant message with content, no tool_calls)
        assistant_msg = messages.reverse.find do |m|
          m["role"] == "assistant" && m["content"] && !m["content"].empty? && !m["tool_calls"]
        end

        # Get timestamps from messages (they're already Time objects)
        started_at = messages.first["created_at"]
        completed_at = messages.last["created_at"]

        # Convert to Time if they're strings
        started_at = Time.parse(started_at) if started_at.is_a?(String)
        completed_at = Time.parse(completed_at) if completed_at.is_a?(String)

        # Update exchange with completion info
        set_clauses = [
          "status = 'completed'",
          "completed_at = '#{completed_at.strftime('%Y-%m-%d %H:%M:%S.%6N')}'",
          "started_at = '#{started_at.strftime('%Y-%m-%d %H:%M:%S.%6N')}'",
          "tokens_input = #{tokens_input}",
          "tokens_output = #{tokens_output}",
          "spend = #{spend}",
          "message_count = #{messages.length}",
          "tool_call_count = #{tool_call_count}"
        ]

        if assistant_msg && assistant_msg["content"]
          set_clauses << "assistant_message = '#{escape_sql(assistant_msg['content'])}'"
        end

        @connection.query(<<~SQL)
          UPDATE exchanges
          SET #{set_clauses.join(', ')}
          WHERE id = #{exchange_id}
        SQL

        # Update all messages with this exchange_id
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
