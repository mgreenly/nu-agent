# frozen_string_literal: true

module Nu
  module Agent
    class Formatter
      attr_writer :orchestrator, :debug
      attr_accessor :exchange_start_time

      def initialize(history:, session_start_time:, conversation_id:, orchestrator:, debug: false, console:, application: nil)
        @history = history
        @session_start_time = session_start_time
        @conversation_id = conversation_id
        @orchestrator = orchestrator
        @debug = debug
        @console = console
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
        @console.hide_spinner if messages.any?

        messages.each do |msg|
          display_message(msg)
          @last_message_id = msg['id']
        end

        # Restart spinner after displaying messages (if still waiting)
        @console.show_spinner("Thinking...") if messages.any? && !@history.workers_idle?
      end

      def wait_for_completion(conversation_id:, poll_interval: 0.1)
        # Start spinner if output_manager is available
        @console.show_spinner("Thinking...")

        loop do
          display_new_messages(conversation_id: conversation_id)

          break if @history.workers_idle?

          sleep poll_interval
        end

        # Display any final messages
        display_new_messages(conversation_id: conversation_id)

        # Stop spinner when done
        @console.hide_spinner
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

        @console.puts("Tokens: #{total_input} in / #{total_output} out / #{total} total")
      end

      def display_thread_event(thread_name, status)
        # Only show in debug mode
        return unless @debug

        # Stop spinner to avoid output on same line
        @console.hide_spinner

        @console.puts("\e[90m[Thread] #{thread_name} #{status}\e[0m")

        # Restart spinner with preserved start time
        @console.show_spinner("Thinking...") unless @history.workers_idle?
      end

      def display_message_created(actor:, role:, redacted: false, content: nil, tool_calls: nil, tool_result: nil)
        # Only show in debug mode
        return unless @debug

        verbosity = @application ? @application.verbosity : 0
        return if verbosity < 2

        # Stop spinner to avoid output on same line
        @console.hide_spinner

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
          @console.puts("\e[90m[Message #{direction}] Created #{msg_type}\e[0m")
          # Restart spinner with preserved start time
          @console.show_spinner("Thinking...") unless @history.workers_idle?
          return
        end

        # Level 3+: Show message creation with details on separate lines
        if verbosity >= 3
          @console.puts("\e[90m[Message #{direction}] Created #{msg_type}\e[0m")
          @console.puts("\e[90m  role: #{role}\e[0m")
          @console.puts("\e[90m  actor: #{actor}\e[0m")

          # Show content preview and/or tool information
          if tool_calls && tool_calls.length > 0
            tool_names = tool_calls.map { |tc| tc['name'] }.join(', ')
            @console.puts("\e[90m  tool_calls: #{tool_names}\e[0m")

            # Show preview of arguments
            tool_calls.each do |tc|
              if tc['arguments'] && !tc['arguments'].empty?
                args_str = tc['arguments'].to_json
                max_length = verbosity >= 6 ? 100 : 30
                preview = args_str[0...max_length]
                @console.puts("\e[90m    #{tc['name']}: #{preview}#{args_str.length > max_length ? '...' : ''}\e[0m")
              end
            end
          end

          if tool_result
            @console.puts("\e[90m  tool_result: #{tool_result['name']}\e[0m")

            # Show preview of result
            if tool_result['result']
              result_str = tool_result['result'].is_a?(Hash) ? tool_result['result'].to_json : tool_result['result'].to_s
              max_length = verbosity >= 6 ? 100 : 30
              preview = result_str[0...max_length]
              @console.puts("\e[90m    result: #{preview}#{result_str.length > max_length ? '...' : ''}\e[0m")
            end
          end

          if content && !content.empty?
            # Level 3-5: Show first 30 chars
            # Level 6+: Show first 100 chars
            max_length = verbosity >= 6 ? 100 : 30
            preview = content[0...max_length]
            @console.puts("\e[90m  content: #{preview}#{content.length > max_length ? '...' : ''}\e[0m")
          end
        end

        # Restart spinner with preserved start time
        @console.show_spinner("Thinking...") unless @history.workers_idle?
      end

      def display_llm_request(messages, tools = nil, markdown_document = nil)
        # Only show in debug mode
        return unless @debug

        # Only show LLM request at verbosity level 4+
        verbosity = @application ? @application.verbosity : 0
        return if verbosity < 4

        # Level 5: Show tools first
        if verbosity >= 5 && tools && !tools.empty?
          @console.puts("\e[90m--- Tools (#{tools.length} available) ---\e[0m")
          tools.each do |tool|
            name = tool['name'] || tool[:name]
            @console.puts("\e[90m  - #{name}\e[0m")
          end
        end

        # Separate history from markdown document
        # The markdown document is always the last message (if present)
        history_messages = markdown_document ? messages[0...-1] : messages

        # Show conversation history (unredacted messages)
        if !history_messages.empty?
          @console.puts("\e[90m--- Conversation History (#{history_messages.length} unredacted message(s)) ---\e[0m")
          history_messages.each_with_index do |msg, i|
            @console.puts("\e[90m  Message #{i + 1} (role: #{msg['role']})\e[0m")
            if msg['content']
              content_preview = msg['content'].to_s[0...200]
              @console.puts("\e[90m  #{content_preview}\e[0m")
              @console.puts("\e[90m  ... (#{msg['content'].to_s.length} chars total)\e[0m") if msg['content'].to_s.length > 200
            end
            if msg['tool_calls']
              @console.puts("\e[90m  [Contains #{msg['tool_calls'].length} tool call(s)]\e[0m")
            end
            if msg['tool_result']
              @console.puts("\e[90m  [Tool result for: #{msg['tool_result']['name']}]\e[0m")
            end
          end
        end

        # Show markdown document (context + tools + user query)
        if markdown_document
          @console.puts("\e[90m--- Exchange Request ---\e[0m")
          # Show first 500 chars of markdown document
          preview = markdown_document[0...500]
          @console.puts("\e[90m#{preview}\e[0m")
          @console.puts("\e[90m... (#{markdown_document.length} chars total)\e[0m") if markdown_document.length > 500
          @console.puts("\e[90m--- Exchange Request ---\e[0m")
        end
      end

      private

      def display_user_message(message)
        # User messages are entered by the user, so we don't need to display them again
        # (they've already been echoed by the REPL)
      end

      def display_assistant_message(message)
        # Display any text content
        if message['content'] && !message['content'].strip.empty?
          @console.puts(message['content'])
        elsif !message['tool_calls'] && message['tokens_output'] && message['tokens_output'] > 0
          # LLM generated output but content is empty (unusual case - possibly API issue)
          @console.puts("\e[90m(LLM returned empty response - this may be an API/model issue)\e[0m") if @debug
        end

        # Display tool calls if present (only in debug mode)
        if @debug && message['tool_calls']
          total_count = message['tool_calls'].length
          message['tool_calls'].each_with_index do |tc, index|
            display_tool_call(tc, index: index + 1, total: total_count)
          end
        end

        # Only show token stats on final message (no tool calls)
        if message['tokens_input'] && message['tokens_output'] && !message['tool_calls']
          # Calculate elapsed time for this exchange
          elapsed_time = nil
          if @exchange_start_time
            elapsed_time = Time.now - @exchange_start_time
          end

          # Query database for session totals (for billing)
          tokens = @history.session_tokens(
            conversation_id: @conversation_id,
            since: @session_start_time
          )

          max_context = @orchestrator.max_context
          percentage = (tokens['total'].to_f / max_context * 100).round(1)

          @console.puts("\e[90mSession tokens: #{tokens['input']} in / #{tokens['output']} out / #{tokens['total']} Total / (#{percentage}% of #{max_context})\e[0m") if @debug
          @console.puts("\e[90mSession spend: $#{'%.6f' % tokens['spend']}\e[0m") if @debug
          if elapsed_time
            @console.puts("\e[90mElapsed time: #{'%.2f' % elapsed_time}s\e[0m") if @debug
          end
        end
      end

      def display_system_message(message)
        content = message['content'].to_s
        return if content.strip.empty?

        # Split and normalize, then prefix first line with [System]
        lines = content.lines.map(&:chomp)
        lines = lines.drop_while(&:empty?).reverse.drop_while(&:empty?).reverse

        # Collapse consecutive blanks
        normalized = []
        prev_empty = false
        lines.each do |line|
          if line.empty?
            normalized << line unless prev_empty
            prev_empty = true
          else
            normalized << line
            prev_empty = false
          end
        end

        if normalized.any?
          @console.puts("[System] #{normalized.first}")
          normalized[1..-1].each { |line| @console.puts(line) }
        end
      end

      def display_spell_checker_message(message)
        role_label = message['role'] == 'user' ? 'Spell Check Request' : 'Spell Check Result'
        @console.puts("\e[90m[#{role_label}]\e[0m")
        if message['content'] && !message['content'].strip.empty?
          @console.puts("\e[90m#{message['content']}\e[0m")
        end
      end

      def display_tool_call(tool_call, index: nil, total: nil)
        # Get verbosity level (default to 0 if application not set)
        verbosity = @application ? @application.verbosity : 0

        # Show count indicator if multiple tool calls
        count_indicator = (index && total && total > 1) ? " (#{index}/#{total})" : ""
        @console.puts("\e[90m[Tool Call Request] #{tool_call['name']}#{count_indicator}\e[0m")

        # Level 0: Show tool name only, no arguments
        if verbosity >= 1
          begin
            if tool_call['arguments'] && !tool_call['arguments'].empty?
              tool_call['arguments'].each do |key, value|
                # Strip to avoid trailing whitespace causing blank lines
                value_str = value.to_s.strip

                # Level 1-3: Truncate each param to 30 characters
                if verbosity < 4
                  if value_str.length > 30
                    @console.puts("\e[90m  #{key}: #{value_str[0...30]}...\e[0m")
                  else
                    @console.puts("\e[90m  #{key}: #{value_str}\e[0m")
                  end
                # Level 4+: Show full value
                else
                  # Handle multiline values to avoid extra blank lines
                  if value_str.include?("\n")
                    @console.puts("\e[90m  #{key}:\e[0m")
                    value_str.lines.each do |line|
                      chomped = line.chomp
                      @console.puts("\e[90m    #{chomped}\e[0m") unless chomped.empty?
                    end
                  else
                    @console.puts("\e[90m  #{key}: #{value_str}\e[0m")
                  end
                end
              end
            end
          rescue => e
            @console.puts("\e[90m  [Error displaying arguments: #{e.message}]\e[0m")
          end
        end
      end

      def display_tool_result(message)
        result = message['tool_result']['result']
        name = message['tool_result']['name']

        # Get verbosity level (default to 0 if application not set)
        verbosity = @application ? @application.verbosity : 0

        @console.puts("\e[90m[Tool Use Response] #{name}\e[0m")

        # Level 0: Show tool name only, no result details
        if verbosity >= 1
          begin
            if result.is_a?(Hash)
              result.each do |key, value|
                # Convert to string and ensure no embedded newlines cause issues
                value_str = value.to_s.strip

                # Level 1-3: Truncate each field to 30 characters
                if verbosity < 4
                  # Handle multiline values - just show first line truncated
                  if value_str.include?("\n")
                    first_line = value_str.lines.first.chomp
                    if first_line.length > 30
                      @console.puts("\e[90m  #{key}: #{first_line[0...30]}...\e[0m")
                    else
                      @console.puts("\e[90m  #{key}: #{first_line}...\e[0m")
                    end
                  elsif value_str.length > 30
                    @console.puts("\e[90m  #{key}: #{value_str[0...30]}...\e[0m")
                  else
                    @console.puts("\e[90m  #{key}: #{value_str}\e[0m")
                  end
                # Level 4+: Show full value
                else
                  # Handle multiline values carefully to avoid extra blank lines
                  if value_str.include?("\n")
                    # Multi-line value: put key on own line, then each value line indented
                    @console.puts("\e[90m  #{key}:\e[0m")
                    # Split and add each line, skipping empty lines
                    value_str.lines.each do |line|
                      chomped = line.chomp
                      @console.puts("\e[90m    #{chomped}\e[0m") unless chomped.empty?
                    end
                  else
                    # Single line value: key and value on same line
                    @console.puts("\e[90m  #{key}: #{value_str}\e[0m")
                  end
                end
              end
            else
              # Non-hash result
              result_str = result.to_s
              if verbosity < 4 && result_str.length > 30
                @console.puts("\e[90m  #{result_str[0...30]}...\e[0m")
              else
                @console.puts("\e[90m  #{result_str}\e[0m")
              end
            end
          rescue => e
            @console.puts("\e[90m  [Error displaying result: #{e.message}]\e[0m")
            @console.puts("\e[90m  [Full result: #{result.inspect}]\e[0m") if @debug
          end
        end
      end

      def display_error(message)
        error = message['error']

        @console.puts("\e[31m#{message['content']}\e[0m")
        @console.puts("\e[31mStatus: #{error['status']}\e[0m")

        @console.puts("\e[31mHeaders:\e[0m")
        error['headers'].each do |key, value|
          @console.puts("\e[31m  #{key}: #{value}\e[0m")
        end

        @console.puts("\e[31mBody:\e[0m")
        # Try to parse and pretty print JSON body
        begin
          if error['body'].is_a?(String) && !error['body'].empty?
            parsed = JSON.parse(error['body'])
            @console.puts("\e[31m#{JSON.pretty_generate(parsed)}\e[0m")
          elsif error['body']
            @console.puts("\e[31m#{error['body']}\e[0m")
          else
            @console.puts("\e[31m(empty)\e[0m")
          end
        rescue JSON::ParserError
          @console.puts("\e[31m#{error['body']}\e[0m")
        end

        # Show raw error for debugging if body is empty
        if error['raw_error'] && (error['body'].nil? || error['body'].empty?)
          @console.puts("\e[31mRaw Error (for debugging):\e[0m")
          @console.puts("\e[31m#{error['raw_error']}\e[0m")
        end
      end
    end
  end
end
