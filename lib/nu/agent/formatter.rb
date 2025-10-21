# frozen_string_literal: true

module Nu
  module Agent
    class Formatter
      def initialize(history:, output: $stdout)
        @history = history
        @output = output
        @last_message_id = 0
      end

      def display_new_messages(conversation_id:)
        messages = @history.messages_since(
          conversation_id: conversation_id,
          message_id: @last_message_id
        )

        messages.each do |msg|
          display_message(msg)
          @last_message_id = msg[:id]
        end
      end

      def wait_for_completion(conversation_id:, poll_interval: 0.1)
        loop do
          display_new_messages(conversation_id: conversation_id)

          break if @history.workers_idle?

          sleep poll_interval
        end

        # Display any final messages
        display_new_messages(conversation_id: conversation_id)
      end

      def display_message(message)
        case message[:role]
        when 'user'
          display_user_message(message)
        when 'assistant'
          display_assistant_message(message)
        when 'system'
          display_system_message(message)
        end
      end

      def display_token_summary(conversation_id:)
        messages = @history.messages(conversation_id: conversation_id, include_in_context_only: false)

        total_input = messages.sum { |m| m[:tokens_input] || 0 }
        total_output = messages.sum { |m| m[:tokens_output] || 0 }
        total = total_input + total_output

        @output.puts "\nTokens: #{total_input} in / #{total_output} out / #{total} total"
      end

      private

      def display_user_message(message)
        # User messages are entered by the user, so we don't need to display them again
        # (they've already been echoed by the REPL)
      end

      def display_assistant_message(message)
        @output.puts "\n#{message[:content]}"

        if message[:tokens_input] && message[:tokens_output]
          total = message[:tokens_input] + message[:tokens_output]
          @output.puts "\nTokens: #{message[:tokens_input]} in / #{message[:tokens_output]} out / #{total} total"
        end
      end

      def display_system_message(message)
        @output.puts "\n[System] #{message[:content]}"
      end
    end
  end
end
