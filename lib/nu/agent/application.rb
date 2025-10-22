# frozen_string_literal: true

module Nu
  module Agent
    class Application
      attr_reader :client, :history, :formatter, :conversation_id, :session_start_time, :summarizer_status, :status_mutex
      attr_accessor :active_threads

      def initialize(options:)
        $stdout.sync = true
        @session_start_time = Time.now
        @options = options
        @user_actor = ENV['USER'] || 'user'
        @debug = @options.debug
        @shutdown = false
        @critical_sections = 0
        @critical_mutex = Mutex.new
        @operation_mutex = Mutex.new
        @client = ModelFactory.create(options.model)
        @history = History.new

        # Load settings from database (default both to true)
        @redact = @history.get_config('redaction', default: 'true') == 'true'
        @summarizer_enabled = @history.get_config('summarizer_enabled', default: 'true') == 'true'
        @conversation_id = @history.create_conversation
        @formatter = Formatter.new(
          history: @history,
          session_start_time: @session_start_time,
          conversation_id: @conversation_id,
          client: @client,
          debug: @debug
        )
        @active_threads = []
        @summarizer_status = {
          'running' => false,
          'total' => 0,
          'completed' => 0,
          'failed' => 0,
          'current_conversation_id' => nil,
          'last_summary' => nil,
          'spend' => 0.0
        }
        @status_mutex = Mutex.new

        # Start background summarization worker
        start_summarization_worker
      end

      def run
        setup_signal_handlers
        print_welcome
        repl
        print_goodbye
      ensure
        # Signal threads to shutdown
        @shutdown = true

        # Wait for any critical sections (database writes) to complete
        timeout = 5.0
        start_time = Time.now
        while in_critical_section? && (Time.now - start_time) < timeout
          sleep 0.1
        end

        # Wait for any active threads to complete (they should exit quickly)
        active_threads.each(&:join)
        history.close if history
      end

      def process_input(input)
        # Handle commands
        if input.start_with?('/')
          return handle_command(input)
        end

        # Add user message to history
        history.add_message(
          conversation_id: conversation_id,
          actor: @user_actor,
          role: 'user',
          content: input
        )

        # Increment workers BEFORE spawning thread
        history.increment_workers

        # Capture values to pass into thread under mutex
        thread = @operation_mutex.synchronize do
          conv_id = conversation_id
          hist = history
          cli = client
          session_start = session_start_time

          # Process in a thread
          Thread.new(conv_id, hist, cli, session_start) do |conversation_id, history, client, session_start_time|
            begin
              chat_loop(
                conversation_id: conversation_id,
                history: history,
                client: client,
                session_start_time: session_start_time
              )
            ensure
              history.decrement_workers
            end
          end
        end

        active_threads << thread

        # Wait for completion and display
        formatter.wait_for_completion(conversation_id: conversation_id)

        # Remove completed thread
        active_threads.delete(thread)

        :continue
      end

      private

      def enter_critical_section
        @critical_mutex.synchronize do
          @critical_sections += 1
        end
      end

      def exit_critical_section
        @critical_mutex.synchronize do
          @critical_sections -= 1
        end
      end

      def in_critical_section?
        @critical_mutex.synchronize do
          @critical_sections > 0
        end
      end

      def chat_loop(conversation_id:, history:, client:, session_start_time:)
        tool_registry = ToolRegistry.new

        # Get the starting message ID to determine which tool results are "old"
        start_messages = history.messages(conversation_id: conversation_id, since: session_start_time)
        start_message_id = start_messages.empty? ? 0 : start_messages.last['id']

        loop do
          # Get messages from history (only from current session)
          messages = history.messages(conversation_id: conversation_id, since: session_start_time)

          # Store original messages for index generation
          original_messages = messages

          # Redact old tool results if redaction is enabled
          if @redact
            messages = redact_old_tool_results(messages, threshold_id: start_message_id)

            # Build and prepend redaction index
            index = build_redaction_index(original_messages, messages)
            if index
              messages.unshift({
                'role' => 'user',
                'content' => index
              })
            end
          end

          # Get tools formatted for this client
          tools = client.format_tools(tool_registry)

          # Call LLM with tools
          response = client.send_message(messages: messages, tools: tools)

          # Check if we got an error response
          if response['error']
            # Save error message and exit
            history.add_message(
              conversation_id: conversation_id,
              actor: 'api_error',
              role: 'assistant',
              content: response['content'],
              model: response['model'],
              error: response['error']
            )
            break
          # If we got tool calls, execute them
          elsif response['tool_calls']
            # Save assistant message with tool calls
            history.add_message(
              conversation_id: conversation_id,
              actor: 'orchestrator',
              role: 'assistant',
              content: response['content'],
              model: response['model'],
              tokens_input: response['tokens']['input'],
              tokens_output: response['tokens']['output'],
              spend: response['spend'],
              tool_calls: response['tool_calls']
            )

            # Execute each tool and save results
            response['tool_calls'].each do |tool_call|
              result = tool_registry.execute(
                name: tool_call['name'],
                arguments: tool_call['arguments'],
                history: history,
                context: { 'conversation_id' => conversation_id, 'application' => self }
              )

              # Save tool result
              # Store both name and result for client formatting
              history.add_message(
                conversation_id: conversation_id,
                actor: tool_call['name'],
                role: 'tool',
                content: nil,
                tool_call_id: tool_call['id'],
                tool_result: {
                  'name' => tool_call['name'],
                  'result' => result
                }
              )
            end

            # Loop back to send results to LLM
            next
          else
            # No tool calls, save final response and exit
            history.add_message(
              conversation_id: conversation_id,
              actor: 'orchestrator',
              role: 'assistant',
              content: response['content'],
              model: response['model'],
              tokens_input: response['tokens']['input'],
              tokens_output: response['tokens']['output'],
              spend: response['spend']
            )

            break
          end
        end
      end

      def redact_old_tool_results(messages, threshold_id:)
        messages.filter_map do |msg|
          # Skip old messages entirely if they meet certain criteria
          if msg['id'] && msg['id'] <= threshold_id
            # Optimization #3: Remove error messages from context
            next nil if msg['error']

            # Optimization #4: Remove intermediate assistant messages (ones with only tool_calls)
            next nil if msg['role'] == 'assistant' && msg['tool_calls'] && !msg['content']

            # Build redacted version of old messages
            redacted = msg.dup

            # Optimization #1: Redact tool_calls arguments
            if redacted['tool_calls']
              redacted['tool_calls'] = redacted['tool_calls'].map do |tc|
                tc.merge('arguments' => { 'redacted' => true })
              end
            end

            # Optimization #2: Redact assistant content when it has tool_calls
            if redacted['role'] == 'assistant' && redacted['tool_calls']
              redacted['content'] = nil
            end

            # Original optimization: Redact tool_result
            if redacted['tool_result']
              redacted['tool_result'] = {
                'name' => redacted['tool_result']['name'],
                'result' => { 'redacted' => true }
              }
            end

            redacted
          else
            # New messages - return as-is
            msg
          end
        end
      end

      def repl
        setup_readline

        loop do
          print "\n"
          input = Readline.readline("> ", true)  # true = add to history

          break if input.nil?  # Ctrl+D

          input = input.strip

          # Remove from history if empty
          if input.empty?
            Readline::HISTORY.pop
            next
          end

          result = process_input(input)
          break if result == :exit
        end
      ensure
        save_history
      end

      def setup_readline
        # Set up tab completion
        commands = ['/clear', '/debug', '/exit', '/fix', '/help', '/info', '/model', '/models', '/redaction', '/reset', '/summarizer']
        all_models = ModelFactory.available_models.values.flatten

        Readline.completion_proc = proc do |str|
          # Check if we're completing after '/model '
          line = Readline.line_buffer
          if line.start_with?('/model ')
            # Complete model names
            prefix_match = line.match(/^\/model\s+(.*)/)
            if prefix_match
              partial = prefix_match[1]
              all_models.grep(/^#{Regexp.escape(partial)}/i)
            else
              all_models
            end
          else
            # Complete commands
            commands.grep(/^#{Regexp.escape(str)}/)
          end
        end

        # Load history from file
        history_file = File.join(Dir.home, '.nu_agent_history')
        if File.exist?(history_file)
          File.readlines(history_file).each do |line|
            Readline::HISTORY.push(line.chomp)
          end
        end
      end

      def save_history
        history_file = File.join(Dir.home, '.nu_agent_history')
        File.open(history_file, 'w') do |f|
          Readline::HISTORY.to_a.last(1000).each { |line| f.puts(line) }
        end
      rescue => e
        # Silently ignore history save errors
      end

      def handle_command(input)
        # Handle /model NAME command (takes argument)
        if input.downcase.start_with?('/model ')
          parts = input.split(' ', 2)
          if parts.length < 2 || parts[1].strip.empty?
            puts "Usage: /model <name>"
            puts "Example: /model gpt-5"
            puts "Run /models to see available models"
            return :continue
          end

          new_model_name = parts[1].strip

          # Switch model under mutex (blocks if thread is running)
          @operation_mutex.synchronize do
            # Wait for active threads to complete
            unless active_threads.empty?
              puts "Waiting for current operation to complete..."
              active_threads.each(&:join)
            end

            # Try to create new client
            begin
              new_client = ModelFactory.create(new_model_name)
            rescue Error => e
              puts "Error: #{e.message}"
              return :continue
            end

            # Switch both client and formatter
            @client = new_client
            @formatter.client = new_client

            puts "Switched to: #{@client.name} (#{@client.model})"
          end

          return :continue
        end

        # Handle /redaction [on/off] command
        if input.downcase.start_with?('/redaction')
          parts = input.split(' ', 2)
          if parts.length < 2 || parts[1].strip.empty?
            puts "Usage: /redaction <on|off>"
            puts "Current: redaction=#{@redact ? 'on' : 'off'}"
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == 'on'
            @redact = true
            history.set_config('redaction', 'true')
            puts "redaction=on"
          elsif setting == 'off'
            @redact = false
            history.set_config('redaction', 'false')
            puts "redaction=off"
          else
            puts "Invalid option. Use: /redaction <on|off>"
          end

          return :continue
        end

        # Handle /summarizer [on/off] command
        if input.downcase.start_with?('/summarizer')
          parts = input.split(' ', 2)
          if parts.length < 2 || parts[1].strip.empty?
            puts "Usage: /summarizer <on|off>"
            puts "Current: summarizer=#{@summarizer_enabled ? 'on' : 'off'}"
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == 'on'
            @summarizer_enabled = true
            history.set_config('summarizer_enabled', 'true')
            puts "summarizer=on"
            puts "Summarizer will start on next /reset"
          elsif setting == 'off'
            @summarizer_enabled = false
            history.set_config('summarizer_enabled', 'false')
            puts "summarizer=off"
          else
            puts "Invalid option. Use: /summarizer <on|off>"
          end

          return :continue
        end

        case input.downcase
        when '/exit'
          :exit
        when '/clear'
          system('clear')
          :continue
        when '/reset'
          @conversation_id = history.create_conversation
          @session_start_time = Time.now
          formatter.reset_session(conversation_id: @conversation_id)
          puts "Conversation reset"

          # Start background summarization worker
          start_summarization_worker

          :continue
        when '/debug'
          @debug = !@debug
          @formatter.debug = @debug
          puts "debug=#{@debug}"
          :continue
        when '/fix'
          run_fix
          :continue
        when '/info'
          print_info
          :continue
        when '/models'
          print_models
          :continue
        when '/help'
          print_help
          :continue
        else
          puts "Unknown command: #{input}"
          :continue
        end
      end

      def print_help
        puts "\nAvailable commands:"
        puts "  /clear              - Clear the screen"
        puts "  /debug              - Toggle debug mode (show/hide tool calls and results)"
        puts "  /exit               - Exit the REPL"
        puts "  /fix                - Scan and fix database corruption issues"
        puts "  /help               - Show this help message"
        puts "  /info               - Show current session information"
        puts "  /model <name>       - Switch to a different model (e.g., /model gpt-5)"
        puts "  /models             - List available models"
        puts "  /redaction <on|off> - Enable/disable redaction of tool results in context"
        puts "  /reset              - Start a new conversation"
        puts "  /summarizer <on|off> - Enable/disable background conversation summarization"
      end

      def run_fix
        puts ""
        puts "Scanning database for corruption..."

        corrupted = history.find_corrupted_messages

        if corrupted.empty?
          puts "✓ No corruption found"
          return
        end

        puts "Found #{corrupted.length} corrupted message(s):"
        corrupted.each do |msg|
          puts "  • Message #{msg['id']}: #{msg['tool_name']} with redacted arguments (#{msg['created_at']})"
        end

        print "\nDelete these messages? [y/N] "
        response = gets.chomp.downcase

        if response == 'y'
          ids = corrupted.map { |m| m['id'] }
          count = history.fix_corrupted_messages(ids)
          puts "✓ Deleted #{count} corrupted message(s)"
        else
          puts "Skipped"
        end
      end

      def print_info
        puts ""
        puts "Version:       #{Nu::Agent::VERSION}"
        puts "Debug mode:    #{@debug}"
        puts "Redaction:     #{@redact ? 'on' : 'off'}"
        puts "Summarizer:    #{@summarizer_enabled ? 'on' : 'off'}"

        # Show summarizer status if enabled
        if @summarizer_enabled
          puts "  Model:       gpt-5-nano"
          @status_mutex.synchronize do
            status = @summarizer_status
            if status['running']
              puts "  Status:      running (#{status['completed']}/#{status['total']} conversations)"
              puts "  Spend:       $#{'%.6f' % status['spend']}" if status['spend'] > 0
            elsif status['total'] > 0
              puts "  Status:      completed (#{status['completed']}/#{status['total']} conversations, #{status['failed']} failed)"
              puts "  Spend:       $#{'%.6f' % status['spend']}" if status['spend'] > 0
            else
              puts "  Status:      idle"
            end
          end
        end

        puts "Database:      #{File.expand_path(history.db_path)}"
      end

      def print_models
        models = ModelFactory.display_models

        puts "\nAvailable Models:"
        puts "  Anthropic: #{models[:anthropic].join(', ')}"
        puts "  Google:    #{models[:google].join(', ')}"
        puts "  OpenAI:    #{models[:openai].join(', ')}"
        puts "  X.AI:      #{models[:xai].join(', ')}"
        puts "\n  Default: gpt-5-nano"
      end

      def setup_signal_handlers
        Signal.trap("INT") do
          @shutdown = true
          print_goodbye
          exit(0)
        end
      end

      def print_welcome
        puts "Nu Agent REPL"
        puts "Using: #{client.name} (#{client.model})"
        puts "Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit."
        puts "Type /help for available commands"
        puts "=" * 60
      end

      def print_goodbye
        puts "\n\nGoodbye!"
      end

      def build_redaction_index(original_messages, redacted_messages)
        # Find which messages were redacted or removed
        redacted_info = []

        original_messages.each do |msg|
          next unless msg['id']

          # Check if this message was removed entirely
          redacted_version = redacted_messages.find { |m| m['id'] == msg['id'] }

          if redacted_version.nil?
            # Message was completely removed
            redacted_info << describe_message(msg)
          elsif message_was_redacted?(msg, redacted_version)
            # Message was redacted but still present
            redacted_info << describe_message(msg)
          end
        end

        return nil if redacted_info.empty?

        # Build index message
        <<~INDEX
          Redacted messages available via read_redacted_message(id):
          #{redacted_info.join("\n")}

          Use this tool when you need full details from earlier messages.
        INDEX
      end

      def message_was_redacted?(original, redacted)
        # Check if content/data was redacted
        return true if original['tool_result'] && redacted['tool_result'] && redacted['tool_result']['result'] == { 'redacted' => true }
        return true if original['tool_calls'] && redacted['tool_calls'] && redacted['tool_calls'].first&.dig('arguments') == { 'redacted' => true }
        return true if original['content'] && !redacted['content']
        false
      end

      def describe_message(msg)
        preview = if msg['content'] && !msg['content'].empty?
          msg['content'][0..50]
        elsif msg['tool_calls']
          "Tool: #{msg['tool_calls'].first['name']}"
        elsif msg['tool_result']
          "Result: #{msg['tool_result']['name']}"
        elsif msg['error']
          "Error: #{msg['error']['status']}"
        else
          "Message"
        end

        "  ##{msg['id']}: [#{msg['role']}] #{preview}... (#{time_ago(msg['created_at'])})"
      end

      def time_ago(timestamp)
        return "unknown" unless timestamp

        begin
          time = timestamp.is_a?(String) ? Time.parse(timestamp) : timestamp
          seconds = (Time.now - time).to_i

          if seconds < 60
            "#{seconds}s ago"
          elsif seconds < 3600
            "#{(seconds / 60)}m ago"
          elsif seconds < 86400
            "#{(seconds / 3600)}h ago"
          else
            "#{(seconds / 86400)}d ago"
          end
        rescue
          "unknown"
        end
      end

      def start_summarization_worker
        # Don't start if summarizer is disabled
        return unless @summarizer_enabled

        # Capture values for thread
        @operation_mutex.synchronize do
          conv_id = conversation_id
          hist = history
          status = @summarizer_status
          status_mtx = @status_mutex
          app = self

          thread = Thread.new(conv_id, hist, status, status_mtx, app) do |current_conversation_id, history, summarizer_status, status_mutex, application|
            begin
              summarize_conversations(
                current_conversation_id: current_conversation_id,
                history: history,
                summarizer_status: summarizer_status,
                status_mutex: status_mutex,
                application: application
              )
            rescue => e
              status_mutex.synchronize do
                summarizer_status['running'] = false
              end
            end
          end

          active_threads << thread
        end
      end

      def summarize_conversations(current_conversation_id:, history:, summarizer_status:, status_mutex:, application:)
        # Get conversations that need summarization
        conversations = history.get_unsummarized_conversations(exclude_id: current_conversation_id)

        if conversations.empty?
          return
        end

        # Update status
        status_mutex.synchronize do
          summarizer_status['running'] = true
          summarizer_status['total'] = conversations.length
          summarizer_status['completed'] = 0
          summarizer_status['failed'] = 0
        end

        # Create a gpt-5-nano client for summarization
        summarizer = ModelFactory.create('gpt-5-nano')

        conversations.each do |conv|
          # Check for shutdown signal before processing each conversation
          break if application.instance_variable_get(:@shutdown)

          conv_id = conv['id']

          # Update current conversation being processed
          status_mutex.synchronize do
            summarizer_status['current_conversation_id'] = conv_id
          end

          begin
            # Get all messages for this conversation
            messages = history.messages(conversation_id: conv_id, include_in_context_only: false)

            # Handle empty conversations
            if messages.empty?
              application.send(:enter_critical_section)
              begin
                history.update_conversation_summary(
                  conversation_id: conv_id,
                  summary: "empty conversation",
                  model: 'gpt-5-nano',
                  cost: 0.0
                )
              ensure
                application.send(:exit_critical_section)
              end

              status_mutex.synchronize do
                summarizer_status['completed'] += 1
                summarizer_status['last_summary'] = "empty conversation"
              end

              next
            end

            # Apply redaction (same as we do for context)
            redacted_messages = redact_old_tool_results(messages, threshold_id: 0)

            # Build prompt for summarization
            context = redacted_messages.map do |msg|
              role = msg['role'] == 'tool' ? 'assistant' : msg['role']
              content = msg['content'] || ''
              "#{role}: #{content}"
            end.join("\n\n")

            summary_prompt = <<~PROMPT
              Summarize this conversation concisely in 2-3 sentences.
              Focus on: what the user wanted, key decisions made, and outcomes.

              Conversation:
              #{context}

              Summary:
            PROMPT

            # Check for shutdown before making expensive LLM call
            break if application.instance_variable_get(:@shutdown)

            # Make LLM call in a separate thread so we can check shutdown while waiting
            llm_thread = Thread.new do
              summarizer.send_message(
                messages: [{ 'role' => 'user', 'content' => summary_prompt }],
                tools: nil
              )
            end

            # Poll the thread, checking for shutdown every 100ms
            response = nil
            loop do
              if llm_thread.join(0.1)  # Try to join with 100ms timeout
                response = llm_thread.value
                break
              end

              # If shutdown requested while waiting, abandon this conversation
              break if application.instance_variable_get(:@shutdown)
            end

            # Skip saving if shutdown was requested
            break if application.instance_variable_get(:@shutdown)

            # Skip if response is nil (shouldn't happen, but be safe)
            next if response.nil?

            if response['error']
              status_mutex.synchronize do
                summarizer_status['failed'] += 1
              end
              next
            end

            summary = response['content']&.strip
            cost = response['spend'] || 0.0

            if summary && !summary.empty?
              # Enter critical section for database write
              application.send(:enter_critical_section)
              begin
                # Update conversation with summary
                history.update_conversation_summary(
                  conversation_id: conv_id,
                  summary: summary,
                  model: 'gpt-5-nano',
                  cost: cost
                )
              ensure
                # Exit critical section
                application.send(:exit_critical_section)
              end

              # Update status and accumulate spend
              status_mutex.synchronize do
                summarizer_status['completed'] += 1
                summarizer_status['last_summary'] = summary
                summarizer_status['spend'] += cost
              end
            else
              status_mutex.synchronize do
                summarizer_status['failed'] += 1
              end
            end

          rescue => e
            status_mutex.synchronize do
              summarizer_status['failed'] += 1
            end
          end
        end

        # Mark as complete
        status_mutex.synchronize do
          summarizer_status['running'] = false
          summarizer_status['current_conversation_id'] = nil
        end
      end

    end
  end
end
