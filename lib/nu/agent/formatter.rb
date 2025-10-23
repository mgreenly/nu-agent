# frozen_string_literal: true

module Nu
  module Agent
    class Formatter
      attr_writer :client, :debug
      attr_accessor :turn_start_time

      def initialize(history:, session_start_time:, conversation_id:, client:, debug: false, output: $stdout, output_manager: nil, application: nil)
        @history = history
        @session_start_time = session_start_time
        @conversation_id = conversation_id
        @client = client
        @debug = debug
        @output = output
        @output_manager = output_manager
        @application = application
        @last_message_id = 0
        @turn_start_time = nil
      end

      def reset_session(conversation_id:)
        @conversation_id = conversation_id
        @session_start_time = Time.now
        @last_message_id = 0
      end

      def display_new_messages(conversation_id:)
        messages = @history.messages_since(
          conversation_id: conversation_id,
          message_id: @last_message_id
        )

        # Stop spinner before displaying any messages
        @output_manager&.stop_waiting if messages.any?

        messages.each do |msg|
          display_message(msg)
          @last_message_id = msg['id']
        end

        # Restart spinner after displaying messages (if still waiting)
        @output_manager&.start_waiting if messages.any? && !@history.workers_idle?
      end

      def wait_for_completion(conversation_id:, poll_interval: 0.1)
        # Start spinner if output_manager is available
        @output_manager&.start_waiting

        loop do
          display_new_messages(conversation_id: conversation_id)

          break if @history.workers_idle?

          sleep poll_interval
        end

        # Display any final messages
        display_new_messages(conversation_id: conversation_id)

        # Stop spinner when done
        @output_manager&.stop_waiting
      end

      def display_message(message)
        # Only show spell_checker messages in debug mode
        return if message['actor'] == 'spell_checker' && !@debug

        # Display spell_checker messages in gray (debug style)
        if message['actor'] == 'spell_checker' && @debug
          display_spell_checker_message(message)
          return
        end

        # Error messages
        if message['error']
          display_error(message)
        # Tool results have role 'user' but include tool_result
        elsif message['tool_result']
          # Only display tool results in debug mode
          display_tool_result(message) if @debug
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
        # Display any text content (with leading newline for section spacing)
        if message['content'] && !message['content'].strip.empty?
          @output.puts "\n#{message['content']}"
        end

        # Display tool calls if present (only in debug mode)
        if @debug && message['tool_calls']
          message['tool_calls'].each do |tc|
            display_tool_call(tc)
          end
        end

        # Only show token stats if:
        # - We're in debug mode (show everything), OR
        # - The message doesn't have tool calls (it's a final response)
        if message['tokens_input'] && message['tokens_output'] && (@debug || !message['tool_calls'])
          # Calculate elapsed time for this turn (only show on final message)
          elapsed_time = nil
          if @turn_start_time && !message['tool_calls']
            elapsed_time = Time.now - @turn_start_time
          end

          # Query database for session totals (for billing)
          tokens = @history.session_tokens(
            conversation_id: @conversation_id,
            since: @session_start_time
          )

          max_context = @client.max_context
          percentage = (tokens['total'].to_f / max_context * 100).round(1)

          # ANSI color codes: \e[90m = gray, \e[0m = reset
          @output.puts "\e[90m"
          @output.puts "Session tokens: #{tokens['input']} in / #{tokens['output']} out / #{tokens['total']} Total / (#{percentage}% of #{max_context})"
          @output.puts "Session spend: $#{'%.6f' % tokens['spend']}"
          if elapsed_time
            @output.puts "Elapsed time: #{'%.2f' % elapsed_time}s"
          end
          @output.print "\e[0m"
        end
      end

      def display_system_message(message)
        @output.puts "\n[System] #{message['content']}"
      end

      def display_spell_checker_message(message)
        role_label = message['role'] == 'user' ? 'Spell Check Request' : 'Spell Check Result'
        @output.puts "\e[90m\n[#{role_label}]"
        if message['content'] && !message['content'].strip.empty?
          @output.puts "#{message['content']}"
        end
        @output.print "\e[0m"
      end

      def display_tool_call(tool_call)
        @output.puts "\e[90m\n[Tool Call] #{tool_call['name']}"

        begin
          if tool_call['arguments'] && !tool_call['arguments'].empty?
            # Get verbosity level (default to 0 if application not set)
            verbosity = @application ? @application.verbosity : 0
            name = tool_call['name']

            tool_call['arguments'].each do |key, value|
              # Hide script/command for execute_python/execute_bash when verbosity <= 1
              if (name == 'execute_python' && key.to_s == 'script') ||
                 (name == 'execute_bash' && key.to_s == 'command')
                if verbosity <= 1
                  @output.puts "  #{key}: [hidden - use /verbosity 2 or higher to show]"
                  next
                end
              end

              @output.puts "  #{key}: #{value}"
            end
          end
        rescue => e
          @output.puts "  [Error displaying arguments: #{e.message}]"
        end

        @output.print "\e[0m"
      end

      def display_tool_result(message)
        result = message['tool_result']['result']
        name = message['tool_result']['name']

        @output.puts "\e[90m\n[Tool Result] #{name}"

        begin
          if result.is_a?(Hash)
            # Get verbosity level (default to 0 if application not set)
            verbosity = @application ? @application.verbosity : 0

            result.each do |key, value|
              # Skip 'content' field for file_read when verbosity <= 1
              if name == 'file_read' && key.to_s == 'content' && verbosity <= 1
                @output.puts "  content: [hidden - use /verbosity 2 or higher to show]"
                next
              end

              # Skip 'stdout' and 'stderr' for execute_python/execute_bash when verbosity <= 1
              if (name == 'execute_python' || name == 'execute_bash') &&
                 (key.to_s == 'stdout' || key.to_s == 'stderr') &&
                 verbosity <= 1
                @output.puts "  #{key}: [hidden - use /verbosity 2 or higher to show]"
                next
              end

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
        rescue => e
          @output.puts "  [Error displaying result: #{e.message}]"
          @output.puts "  [Full result: #{result.inspect}]" if @debug
        end

        @output.print "\e[0m"
      end

      def display_error(message)
        error = message['error']

        @output.puts "\n#{message['content']}"
        @output.puts "\nStatus: #{error['status']}"

        @output.puts "\nHeaders:"
        error['headers'].each do |key, value|
          @output.puts "  #{key}: #{value}"
        end

        @output.puts "\nBody:"
        # Try to parse and pretty print JSON body
        begin
          if error['body'].is_a?(String) && !error['body'].empty?
            parsed = JSON.parse(error['body'])
            @output.puts JSON.pretty_generate(parsed)
          elsif error['body']
            @output.puts error['body']
          else
            @output.puts "(empty)"
          end
        rescue JSON::ParserError
          @output.puts error['body']
        end

        # Show raw error for debugging if body is empty
        if error['raw_error'] && (error['body'].nil? || error['body'].empty?)
          @output.puts "\nRaw Error (for debugging):"
          @output.puts error['raw_error']
        end
      end
    end
  end
end
