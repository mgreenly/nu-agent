# frozen_string_literal: true

module Nu
  module Agent
    class Formatter
      attr_writer :orchestrator, :debug
      attr_accessor :exchange_start_time

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
        @exchange_start_time = nil
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
        # Only show in debug mode
        return unless @debug

        # Stop spinner to avoid output on same line
        @output_manager&.stop_waiting
        @output.puts "\n\e[90m[Thread] #{thread_name} #{status}\e[0m"
        # Restart spinner with preserved start time
        @output_manager&.start_waiting("Thinking...", start_time: @exchange_start_time) unless @history.workers_idle?
      end

      def display_message_created(actor:, role:, redacted: false, content: nil, tool_calls: nil, tool_result: nil)
        # Only show in debug mode
        return unless @debug

        verbosity = @application ? @application.verbosity : 0
        return if verbosity < 2

        # Stop spinner to avoid output on same line
        @output_manager&.stop_waiting

        # Determine message direction based on role (from code's perspective)
        # Out = sent to LLM, In = received from LLM
        direction = case role
        when 'user', 'tool', 'system'
          'Out'
        when 'assistant'
          'In'
        else
          ''
        end

        # Level 2: Basic notification
        msg_type = redacted ? "redacted message" : "message"

        if verbosity == 2
          @output.puts "\n\e[90m[Message #{direction}] Created #{msg_type}\e[0m"
          # Restart spinner with preserved start time
          @output_manager&.start_waiting("Thinking...", start_time: @exchange_start_time) unless @history.workers_idle?
          return
        end

        # Level 3+: Show message creation with details on separate lines
        if verbosity >= 3
          @output.puts "\n\e[90m[Message #{direction}] Created #{msg_type}"
          @output.puts "  role: #{role}"
          @output.puts "  actor: #{actor}"

          # Show content preview and/or tool information
          if tool_calls && tool_calls.length > 0
            tool_names = tool_calls.map { |tc| tc['name'] }.join(', ')
            @output.puts "  tool_calls: #{tool_names}"

            # Show preview of arguments
            tool_calls.each do |tc|
              if tc['arguments'] && !tc['arguments'].empty?
                args_str = tc['arguments'].to_json
                max_length = verbosity >= 6 ? 100 : 30
                preview = args_str[0...max_length]
                @output.puts "    #{tc['name']}: #{preview}#{args_str.length > max_length ? '...' : ''}"
              end
            end
          end

          if tool_result
            @output.puts "  tool_result: #{tool_result['name']}"

            # Show preview of result
            if tool_result['result']
              result_str = tool_result['result'].is_a?(Hash) ? tool_result['result'].to_json : tool_result['result'].to_s
              max_length = verbosity >= 6 ? 100 : 30
              preview = result_str[0...max_length]
              @output.puts "    result: #{preview}#{result_str.length > max_length ? '...' : ''}"
            end
          end

          if content && !content.empty?
            # Level 3-5: Show first 30 chars
            # Level 6+: Show first 100 chars
            max_length = verbosity >= 6 ? 100 : 30
            preview = content[0...max_length]
            @output.puts "  content: #{preview}#{content.length > max_length ? '...' : ''}"
          end

          @output.print "\e[0m"
        end

        # Restart spinner with preserved start time
        @output_manager&.start_waiting("Thinking...", start_time: @exchange_start_time) unless @history.workers_idle?
      end

      def display_llm_request(messages, tools = nil, markdown_document = nil)
        # Only show in debug mode
        return unless @debug

        # Only show LLM request at verbosity level 4+
        verbosity = @application ? @application.verbosity : 0
        return if verbosity < 4

        @output.puts "\e[90m"

        # Level 5: Show tools first
        if verbosity >= 5 && tools && !tools.empty?
          @output.puts "\n--- Tools (#{tools.length} available) ---"
          tools.each do |tool|
            name = tool['name'] || tool[:name]
            @output.puts "  - #{name}"
          end
        end

        # Separate history from markdown document
        # The markdown document is always the last message (if present)
        history_messages = markdown_document ? messages[0...-1] : messages

        # Show conversation history (unredacted messages)
        if !history_messages.empty?
          @output.puts "\n--- Conversation History (#{history_messages.length} unredacted message(s)) ---"
          history_messages.each_with_index do |msg, i|
            @output.puts "\n  Message #{i + 1} (role: #{msg['role']})"
            if msg['content']
              content_preview = msg['content'].to_s[0...200]
              @output.puts "  #{content_preview}"
              @output.puts "  ... (#{msg['content'].to_s.length} chars total)" if msg['content'].to_s.length > 200
            end
            if msg['tool_calls']
              @output.puts "  [Contains #{msg['tool_calls'].length} tool call(s)]"
            end
            if msg['tool_result']
              @output.puts "  [Tool result for: #{msg['tool_result']['name']}]"
            end
          end
        end

        # Show markdown document (context + tools + user query)
        if markdown_document
          @output.puts "\n--- Exchange Request ---"
          # Show first 500 chars of markdown document
          preview = markdown_document[0...500]
          @output.puts preview
          @output.puts "... (#{markdown_document.length} chars total)" if markdown_document.length > 500
          @output.puts "--- Exchange Request ---"
        end

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
        elsif !message['tool_calls'] && message['tokens_output'] && message['tokens_output'] > 0
          # LLM generated output but content is empty (unusual case - possibly API issue)
          @output.puts "\n\e[90m(LLM returned empty response - this may be an API/model issue)\e[0m"
        end

        # Display tool calls if present (only in debug mode)
        if @debug && message['tool_calls']
          total_count = message['tool_calls'].length
          message['tool_calls'].each_with_index do |tc, index|
            display_tool_call(tc, index: index + 1, total: total_count)
          end
        end

        # Only show token stats if:
        # - We're in debug mode (show everything), OR
        # - The message doesn't have tool calls (it's a final response)
        if message['tokens_input'] && message['tokens_output'] && (@debug || !message['tool_calls'])
          # Calculate elapsed time for this exchange (only show on final message)
          elapsed_time = nil
          if @exchange_start_time && !message['tool_calls']
            elapsed_time = Time.now - @exchange_start_time
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

      def display_tool_call(tool_call, index: nil, total: nil)
        # Get verbosity level (default to 0 if application not set)
        verbosity = @application ? @application.verbosity : 0

        # Show count indicator if multiple tool calls
        count_indicator = (index && total && total > 1) ? " (#{index}/#{total})" : ""
        @output.puts "\e[90m\n[Tool Call Request] #{tool_call['name']}#{count_indicator}"

        # Level 0: Show tool name only, no arguments
        if verbosity < 1
          @output.print "\e[0m"
          return
        end

        begin
          if tool_call['arguments'] && !tool_call['arguments'].empty?
            tool_call['arguments'].each do |key, value|
              value_str = value.to_s

              # Level 1-3: Truncate each param to 30 characters
              if verbosity < 4
                if value_str.length > 30
                  @output.puts "  #{key}: #{value_str[0...30]}..."
                else
                  @output.puts "  #{key}: #{value_str}"
                end
              # Level 4+: Show full value
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

        @output.puts "\e[90m\n[Tool Use Response] #{name}"

        # Level 0: Show tool name only, no result details
        if verbosity < 1
          @output.print "\e[0m"
          return
        end

        begin
          if result.is_a?(Hash)
            result.each do |key, value|
              value_str = value.to_s

              # Level 1-3: Truncate each field to 30 characters
              if verbosity < 4
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
              # Level 4+: Show full value
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
            if verbosity < 4 && result_str.length > 30
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
