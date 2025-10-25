# frozen_string_literal: true

module Nu
  module Agent
    class Formatter
      attr_writer :orchestrator, :debug
      attr_accessor :turn_start_time

      def initialize(history:, session_start_time:, conversation_id:, orchestrator:, debug: false, output: $stdout, output_manager: nil, application: nil)
        @history = history
        @session_start_time = session_start_time
        @conversation_id = conversation_id
        @orchestrator = orchestrator
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

      def display_thread_event(thread_name, status)
        # Only show thread events at verbosity level 1+
        verbosity = @application ? @application.verbosity : 0
        return if verbosity < 1

        @output.puts "\e[90m[Thread] #{thread_name} #{status}\e[0m"
      end

      def display_llm_request(messages, tools = nil)
        # Only show LLM request at verbosity level 3+
        verbosity = @application ? @application.verbosity : 0
        return if verbosity < 3

        @output.puts "\e[90m"
        @output.puts "\n" + "=" * 80
        @output.puts "[LLM Request] Sending #{messages.length} message(s) to model"
        @output.puts "=" * 80

        messages.each_with_index do |msg, i|
          @output.puts "\n--- Message #{i + 1} (role: #{msg['role']}) ---"
          if msg['content']
            content_preview = msg['content'].to_s[0...200]
            @output.puts content_preview
            @output.puts "... (#{msg['content'].to_s.length} chars total)" if msg['content'].to_s.length > 200
          end
          if msg['tool_calls']
            @output.puts "  [Contains #{msg['tool_calls'].length} tool call(s)]"
          end
          if msg['tool_result']
            @output.puts "  [Tool result for: #{msg['tool_result']['name']}]"
          end
        end

        # Level 4: Also show tools
        if verbosity >= 4 && tools && !tools.empty?
          @output.puts "\n--- Tools (#{tools.length} available) ---"
          tools.each do |tool|
            name = tool['name'] || tool[:name]
            @output.puts "  - #{name}"
          end
        end

        @output.puts "=" * 80
        @output.print "\e[0m"
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

          max_context = @orchestrator.max_context
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
        # Get verbosity level (default to 0 if application not set)
        verbosity = @application ? @application.verbosity : 0

        @output.puts "\e[90m\n[Tool Call] #{tool_call['name']}"

        # Level 0: Show tool name only, no arguments
        if verbosity == 0
          @output.print "\e[0m"
          return
        end

        begin
          if tool_call['arguments'] && !tool_call['arguments'].empty?
            tool_call['arguments'].each do |key, value|
              value_str = value.to_s

              # Level 1: Truncate each param to 30 characters
              if verbosity == 1
                if value_str.length > 30
                  @output.puts "  #{key}: #{value_str[0...30]}..."
                else
                  @output.puts "  #{key}: #{value_str}"
                end
              # Level 2+: Show full value
              else
                @output.puts "  #{key}: #{value_str}"
              end
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

        # Get verbosity level (default to 0 if application not set)
        verbosity = @application ? @application.verbosity : 0

        @output.puts "\e[90m\n[Tool Result] #{name}"

        # Level 0: Show tool name only, no result details
        if verbosity == 0
          @output.print "\e[0m"
          return
        end

        begin
          if result.is_a?(Hash)
            result.each do |key, value|
              value_str = value.to_s

              # Level 1: Truncate each field to 30 characters
              if verbosity == 1
                # Handle multiline values - just show first line truncated
                if value_str.include?("\n")
                  first_line = value_str.lines.first.chomp
                  if first_line.length > 30
                    @output.puts "  #{key}: #{first_line[0...30]}..."
                  else
                    @output.puts "  #{key}: #{first_line}..."
                  end
                elsif value_str.length > 30
                  @output.puts "  #{key}: #{value_str[0...30]}..."
                else
                  @output.puts "  #{key}: #{value_str}"
                end
              # Level 2+: Show full value
              else
                # Format multiline values with proper indentation
                if value_str.include?("\n")
                  @output.puts "  #{key}:"
                  value_str.lines.each { |line| @output.puts "    #{line}" }
                else
                  @output.puts "  #{key}: #{value_str}"
                end
              end
            end
          else
            # Non-hash result
            result_str = result.to_s
            if verbosity == 1 && result_str.length > 30
              @output.puts "  #{result_str[0...30]}..."
            else
              @output.puts "  #{result_str}"
            end
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
