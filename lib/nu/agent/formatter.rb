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
          @last_message_id = msg['id']
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
        # Tool results have role 'user' but include tool_result
        if message['tool_result']
          display_tool_result(message)
        else
          case message['role']
          when 'user'
            display_user_message(message)
          when 'assistant'
            display_assistant_message(message)
          when 'system'
            display_system_message(message)
          end
        end
      end

      def display_token_summary(conversation_id:)
        messages = @history.messages(conversation_id: conversation_id, include_in_context_only: false)

        total_input = messages.sum { |m| m['tokens_input'] || 0 }
        total_output = messages.sum { |m| m['tokens_output'] || 0 }
        total = total_input + total_output

        @output.puts "\nTokens: #{total_input} in / #{total_output} out / #{total} total"
      end

      private

      def display_user_message(message)
        # User messages are entered by the user, so we don't need to display them again
        # (they've already been echoed by the REPL)
      end

      def display_assistant_message(message)
        # Display any text content
        @output.puts "\n#{message['content']}" if message['content']

        # Display tool calls if present
        if message['tool_calls']
          message['tool_calls'].each do |tc|
            display_tool_call(tc)
          end
        end

        if message['tokens_input'] && message['tokens_output']
          total = message['tokens_input'] + message['tokens_output']
          @output.puts "\nTokens: #{message['tokens_input']} in / #{message['tokens_output']} out / #{total} total"
        end
      end

      def display_system_message(message)
        @output.puts "\n[System] #{message['content']}"
      end

      def display_tool_call(tool_call)
        @output.puts "\n[Tool Call] #{tool_call['name']}"
        if tool_call['arguments'] && !tool_call['arguments'].empty?
          tool_call['arguments'].each do |key, value|
            @output.puts "  #{key}: #{value}"
          end
        end
      end

      def display_tool_result(message)
        result = message['tool_result']['result']
        name = message['tool_result']['name']

        @output.puts "\n[Tool Result] #{name}"
        if result.is_a?(Hash)
          result.each do |key, value|
            # Format multiline values (like stdout/stderr) with proper indentation
            if value.to_s.include?("\n")
              @output.puts "  #{key}:"
              value.to_s.lines.each { |line| @output.puts "    #{line}" }
            else
              @output.puts "  #{key}: #{value}"
            end
          end
        else
          @output.puts "  #{result}"
        end
      end
    end
  end
end
