# frozen_string_literal: true

module Nu
  module Agent
    class Application
      attr_reader :orchestrator, :history, :formatter, :conversation_id, :session_start_time, :summarizer_status, :status_mutex, :output, :verbosity
      attr_accessor :active_threads

      def initialize(options:)
        $stdout.sync = true
        @session_start_time = Time.now
        @options = options
        @user_actor = ENV['USER'] || 'user'
        @shutdown = false
        @critical_sections = 0
        @critical_mutex = Mutex.new
        @operation_mutex = Mutex.new
        @history = History.new

        # Load or initialize model configurations
        orchestrator_model = @history.get_config('model_orchestrator')
        spellchecker_model = @history.get_config('model_spellchecker')
        summarizer_model = @history.get_config('model_summarizer')

        # Handle --reset-model flag
        if @options.reset_model
          @history.set_config('model_orchestrator', @options.reset_model)
          @history.set_config('model_spellchecker', @options.reset_model)
          @history.set_config('model_summarizer', @options.reset_model)
          orchestrator_model = @options.reset_model
          spellchecker_model = @options.reset_model
          summarizer_model = @options.reset_model
        elsif orchestrator_model.nil? || spellchecker_model.nil? || summarizer_model.nil?
          # Models not configured and no reset flag provided
          raise Error, "Models not configured. Run with --reset-models <model_name> to initialize."
        end

        # Create client instances with configured models
        @orchestrator = ClientFactory.create(orchestrator_model)
        @spellchecker = ClientFactory.create(spellchecker_model)
        @summarizer = ClientFactory.create(summarizer_model)

        # Load settings from database (default all to true, except debug which defaults to false)
        @debug = @history.get_config('debug', default: 'false') == 'true'
        @debug = true if @options.debug  # Command line option overrides database setting
        @output = OutputManager.new(debug: @debug)
        @redact = @history.get_config('redaction', default: 'true') == 'true'
        @summarizer_enabled = @history.get_config('summarizer_enabled', default: 'true') == 'true'
        @spell_check_enabled = @history.get_config('spell_check_enabled', default: 'true') == 'true'
        @verbosity = @history.get_config('verbosity', default: '0').to_i
        @conversation_id = @history.create_conversation
        @formatter = Formatter.new(
          history: @history,
          session_start_time: @session_start_time,
          conversation_id: @conversation_id,
          orchestrator: @orchestrator,
          debug: @debug,
          output_manager: @output,
          application: self
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

        # Capture the last message ID before this turn starts
        start_messages = history.messages(conversation_id: conversation_id, since: session_start_time)
        turn_start_message_id = start_messages.empty? ? 0 : start_messages.last['id']

        # Capture turn start time for elapsed time calculation
        @formatter.turn_start_time = Time.now

        # Start spinner before spell check (with elapsed time tracking)
        @output.start_waiting("Thinking...", start_time: @formatter.turn_start_time)

        thread = nil
        workers_incremented = false

        begin
          # Run spell checker if enabled
          if @spell_check_enabled
            spell_checker = SpellChecker.new(
              history: history,
              conversation_id: conversation_id,
              client: @spellchecker
            )
            input = spell_checker.check_spelling(input)
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
          workers_incremented = true

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

          # Mark messages from this turn as redacted for future turns
          @output.debug("\n[Redaction]\nMarking tool calls and results as redacted.")
          history.mark_turn_as_redacted(
            conversation_id: conversation_id,
            since_message_id: turn_start_message_id
          )
        rescue Interrupt
          # Ctrl-C pressed - abort all operations and return to prompt
          @output.stop_waiting
          print "\e[90m\n(Ctrl-C) Operation aborted by user.\e[0m\n"

          # Kill all active threads (main chat loop, summarizer, etc.)
          active_threads.each do |t|
            t.kill if t.alive?
          end
          active_threads.clear

          # Clean up worker count if needed
          if thread && thread.alive?
            history.decrement_workers
          elsif workers_incremented
            # Workers were incremented but thread wasn't created yet
            history.decrement_workers
          end
        ensure
          # Always stop the waiting spinner
          @output.stop_waiting
          # Remove completed thread
          active_threads.delete(thread) if thread
        end

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
            # Debug: show redaction status before
            redacted_count = original_messages.count { |m| m['redacted'] }
            @output.debug("\n[redaction] Messages: #{original_messages.length} total, #{redacted_count} marked as redacted")

            messages = redact_old_tool_results(messages)

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

      def redact_old_tool_results(messages)
        messages.filter_map do |msg|
          # Skip redacted messages entirely if they meet certain criteria
          if msg['redacted']
            # Remove error messages from context
            next nil if msg['error']

            # Remove tool result messages (role='tool') - can't have them without tool_calls
            next nil if msg['role'] == 'tool'

            # Remove spell checker messages entirely
            next nil if msg['actor'] == 'spell_checker'

            # Remove intermediate assistant messages (ones with only tool_calls)
            next nil if msg['role'] == 'assistant' && msg['tool_calls'] && !msg['content']

            # Build redacted version of redacted messages
            redacted = msg.dup

            # Remove tool_calls entirely from redacted messages
            redacted.delete('tool_calls') if redacted['tool_calls']

            # Redact tool_result
            if redacted['tool_result']
              redacted['tool_result'] = {
                'name' => redacted['tool_result']['name'],
                'result' => { 'redacted' => true }
              }
            end

            redacted
          else
            # Non-redacted messages - return as-is
            msg
          end
        end
      end

      def repl
        setup_readline

        loop do
          print "\n"

          begin
            input = Readline.readline("> ", true)  # true = add to history
          rescue Interrupt
            # Ctrl-C while waiting for input - exit program
            puts "\n"
            break
          end

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
        commands = ['/clear', '/debug', '/exit', '/fix', '/help', '/info', '/model', '/models', '/redaction', '/reset', '/spellcheck', '/summarizer', '/tools', '/verbosity']
        all_models = ClientFactory.available_models.values.flatten

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
        # Handle /model command with subcommands
        parts = input.split(' ')
        if parts.first&.downcase == '/model'

          # /model without arguments - show current models
          if parts.length == 1
            @output.output("Current Models:")
            @output.output("  Orchestrator:  #{@orchestrator.model}")
            @output.output("  Spellchecker:  #{@spellchecker.model}")
            @output.output("  Summarizer:    #{@summarizer.model}")
            return :continue
          end

          # /model <subcommand> <name>
          if parts.length < 3
            @output.output("Usage:")
            @output.output("  /model                        Show current models")
            @output.output("  /model orchestrator <name>    Set orchestrator model")
            @output.output("  /model spellchecker <name>    Set spellchecker model")
            @output.output("  /model summarizer <name>      Set summarizer model")
            @output.output("")
            @output.output("Example: /model orchestrator gpt-5")
            @output.output("Run /models to see available models")
            return :continue
          end

          subcommand = parts[1].strip.downcase
          new_model_name = parts[2].strip

          case subcommand
          when 'orchestrator'
            # Switch model under mutex (blocks if thread is running)
            @operation_mutex.synchronize do
              # Wait for active threads to complete
              unless active_threads.empty?
                still_running = active_threads.any? do |thread|
                  !thread.join(0.05)
                end

                if still_running
                  @output.output("Waiting for current operation to complete...")
                  active_threads.each(&:join)
                end
              end

              # Try to create new client
              begin
                new_client = ClientFactory.create(new_model_name)
              rescue Error => e
                @output.error("Error: #{e.message}")
                return :continue
              end

              # Switch both orchestrator and formatter
              @orchestrator = new_client
              @formatter.orchestrator = new_client
              @history.set_config('model_orchestrator', new_model_name)

              @output.output("Switched orchestrator to: #{@orchestrator.name} (#{@orchestrator.model})")
            end

          when 'spellchecker'
            begin
              # Create new client
              new_client = ClientFactory.create(new_model_name)
              @spellchecker = new_client
              @history.set_config('model_spellchecker', new_model_name)
              @output.output("Switched spellchecker to: #{new_model_name}")
            rescue Error => e
              @output.error("Error: #{e.message}")
            end

          when 'summarizer'
            begin
              # Create new client
              new_client = ClientFactory.create(new_model_name)
              @summarizer = new_client
              @history.set_config('model_summarizer', new_model_name)
              @output.output("Switched summarizer to: #{new_model_name}")
              @output.output("Note: Change takes effect at the start of the next session (/reset)")
            rescue Error => e
              @output.error("Error: #{e.message}")
            end

          else
            @output.output("Unknown subcommand: #{subcommand}")
            @output.output("Valid subcommands: orchestrator, spellchecker, summarizer")
          end

          return :continue
        end

        # Handle /redaction [on/off] command
        if input.downcase.start_with?('/redaction')
          parts = input.split(' ', 2)
          if parts.length < 2 || parts[1].strip.empty?
            @output.output("Usage: /redaction <on|off>")
            @output.output("Current: redaction=#{@redact ? 'on' : 'off'}")
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == 'on'
            @redact = true
            history.set_config('redaction', 'true')
            @output.output("redaction=on")
          elsif setting == 'off'
            @redact = false
            history.set_config('redaction', 'false')
            @output.output("redaction=off")
          else
            @output.output("Invalid option. Use: /redaction <on|off>")
          end

          return :continue
        end

        # Handle /summarizer [on/off] command
        if input.downcase.start_with?('/summarizer')
          parts = input.split(' ', 2)
          if parts.length < 2 || parts[1].strip.empty?
            @output.output("Usage: /summarizer <on|off>")
            @output.output("Current: summarizer=#{@summarizer_enabled ? 'on' : 'off'}")
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == 'on'
            @summarizer_enabled = true
            history.set_config('summarizer_enabled', 'true')
            @output.output("summarizer=on")
            @output.output("Summarizer will start on next /reset")
          elsif setting == 'off'
            @summarizer_enabled = false
            history.set_config('summarizer_enabled', 'false')
            @output.output("summarizer=off")
          else
            @output.output("Invalid option. Use: /summarizer <on|off>")
          end

          return :continue
        end

        # Handle /spellcheck [on/off] command
        if input.downcase.start_with?('/spellcheck')
          parts = input.split(' ', 2)
          if parts.length < 2 || parts[1].strip.empty?
            @output.output("Usage: /spellcheck <on|off>")
            @output.output("Current: spellcheck=#{@spell_check_enabled ? 'on' : 'off'}")
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == 'on'
            @spell_check_enabled = true
            history.set_config('spell_check_enabled', 'true')
            @output.output("spellcheck=on")
          elsif setting == 'off'
            @spell_check_enabled = false
            history.set_config('spell_check_enabled', 'false')
            @output.output("spellcheck=off")
          else
            @output.output("Invalid option. Use: /spellcheck <on|off>")
          end

          return :continue
        end

        # Handle /debug [on/off] command
        if input.downcase.start_with?('/debug')
          parts = input.split(' ', 2)
          if parts.length < 2 || parts[1].strip.empty?
            @output.output("Usage: /debug <on|off>")
            @output.output("Current: debug=#{@debug ? 'on' : 'off'}")
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == 'on'
            @debug = true
            @formatter.debug = true
            @output.debug = true
            history.set_config('debug', 'true')
            @output.output("debug=on")
          elsif setting == 'off'
            @debug = false
            @formatter.debug = false
            @output.debug = false
            history.set_config('debug', 'false')
            @output.output("debug=off")
          else
            @output.output("Invalid option. Use: /debug <on|off>")
          end

          return :continue
        end

        # Handle /verbosity [NUM] command
        if input.downcase.start_with?('/verbosity')
          parts = input.split(' ', 2)
          if parts.length < 2 || parts[1].strip.empty?
            @output.output("Usage: /verbosity <number>")
            @output.output("Current: verbosity=#{@verbosity}")
            return :continue
          end

          value = parts[1].strip
          if value =~ /^\d+$/
            @verbosity = value.to_i
            history.set_config('verbosity', value)
            @output.output("verbosity=#{@verbosity}")
          else
            @output.output("Invalid option. Use: /verbosity <number>")
          end

          return :continue
        end

        case input.downcase
        when '/exit'
          :exit
        when '/clear'
          system('clear')
          :continue
        when '/tools'
          print_tools
          :continue
        when '/reset'
          @conversation_id = history.create_conversation
          @session_start_time = Time.now
          formatter.reset_session(conversation_id: @conversation_id)
          @output.output("Conversation reset")

          # Start background summarization worker
          start_summarization_worker

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
          @output.output("Unknown command: #{input}")
          :continue
        end
      end

      def print_help
        @output.output("\nAvailable commands:")
        @output.output("  /clear                         - Clear the screen")
        @output.output("  /debug <on|off>                - Enable/disable debug mode (show/hide tool calls and results)")
        @output.output("  /exit                          - Exit the REPL")
        @output.output("  /fix                           - Scan and fix database corruption issues")
        @output.output("  /help                          - Show this help message")
        @output.output("  /info                          - Show current session information")
        @output.output("  /model orchestrator <name>     - Switch orchestrator model")
        @output.output("  /model spellchecker <name>     - Switch spellchecker model")
        @output.output("  /model summarizer <name>       - Switch summarizer model")
        @output.output("  /models                        - List available models")
        @output.output("  /redaction <on|off>            - Enable/disable redaction of tool results in context")
        @output.output("  /verbosity <number>            - Set verbosity level for debug output (default: 0)")
        @output.output("  /reset                         - Start a new conversation")
        @output.output("  /spellcheck <on|off>           - Enable/disable automatic spell checking of user input")
        @output.output("  /summarizer <on|off>           - Enable/disable background conversation summarization")
        @output.output("  /tools                         - List available tools")
      end

      def run_fix
        @output.output("")
        @output.output("Scanning database for corruption...")

        corrupted = history.find_corrupted_messages

        if corrupted.empty?
          @output.output("✓ No corruption found")
          return
        end

        @output.output("Found #{corrupted.length} corrupted message(s):")
        corrupted.each do |msg|
          @output.output("  • Message #{msg['id']}: #{msg['tool_name']} with redacted arguments (#{msg['created_at']})")
        end

        print "\nDelete these messages? [y/N] "
        response = gets.chomp.downcase

        if response == 'y'
          ids = corrupted.map { |m| m['id'] }
          count = history.fix_corrupted_messages(ids)
          @output.output("✓ Deleted #{count} corrupted message(s)")
        else
          @output.output("Skipped")
        end
      end

      def print_info
        @output.output("")
        @output.output("Version:       #{Nu::Agent::VERSION}")

        # Models section
        @output.output("Models:")
        @output.output("  Orchestrator:  #{@orchestrator.model}")
        @output.output("  Spellchecker:  #{@spellchecker.model}")
        @output.output("  Summarizer:    #{@summarizer.model}")

        @output.output("Debug mode:    #{@debug}")
        @output.output("Verbosity:     #{@verbosity}")
        @output.output("Redaction:     #{@redact ? 'on' : 'off'}")
        @output.output("Summarizer:    #{@summarizer_enabled ? 'on' : 'off'}")

        # Show summarizer status if enabled
        if @summarizer_enabled
          @status_mutex.synchronize do
            status = @summarizer_status
            if status['running']
              @output.output("  Status:      running (#{status['completed']}/#{status['total']} conversations)")
              @output.output("  Spend:       $#{'%.6f' % status['spend']}") if status['spend'] > 0
            elsif status['total'] > 0
              @output.output("  Status:      completed (#{status['completed']}/#{status['total']} conversations, #{status['failed']} failed)")
              @output.output("  Spend:       $#{'%.6f' % status['spend']}") if status['spend'] > 0
            else
              @output.output("  Status:      idle")
            end
          end
        end

        @output.output("Spellcheck:    #{@spell_check_enabled ? 'on' : 'off'}")
        @output.output("Database:      #{File.expand_path(history.db_path)}")
      end

      def print_models
        models = ClientFactory.display_models

        # Get defaults from each client
        anthropic_default = Nu::Agent::Clients::Anthropic::DEFAULT_MODEL
        google_default = Nu::Agent::Clients::Google::DEFAULT_MODEL
        openai_default = Nu::Agent::Clients::OpenAI::DEFAULT_MODEL
        xai_default = Nu::Agent::Clients::XAI::DEFAULT_MODEL

        # Mark defaults with asterisk
        anthropic_list = models[:anthropic].map { |m| m == anthropic_default ? "#{m}*" : m }.join(', ')
        google_list = models[:google].map { |m| m == google_default ? "#{m}*" : m }.join(', ')
        openai_list = models[:openai].map { |m| m == openai_default ? "#{m}*" : m }.join(', ')
        xai_list = models[:xai].map { |m| m == xai_default ? "#{m}*" : m }.join(', ')

        @output.output("\nAvailable Models (* = default):")
        @output.output("  Anthropic: #{anthropic_list}")
        @output.output("  Google:    #{google_list}")
        @output.output("  OpenAI:    #{openai_list}")
        @output.output("  X.AI:      #{xai_list}")
      end

      def print_tools
        tool_registry = ToolRegistry.new

        @output.output("\nAvailable Tools:")
        tool_registry.all.each do |tool|
          # Get first sentence of description
          desc = tool.description.split(/\.\s+/).first || tool.description
          desc = desc.strip
          desc += "." unless desc.end_with?(".")

          @output.output("  #{tool.name.ljust(25)} - #{desc}")
        end
      end

      def setup_signal_handlers
        # Don't trap INT - let it raise Interrupt exception so we can handle it gracefully
        # Signal.trap("INT") do
        #   @shutdown = true
        #   print_goodbye
        #   exit(0)
        # end
      end

      def print_welcome
        print "\033[2J\033[H"
        @output.output("Nu Agent REPL")
        @output.output("Using: #{orchestrator.name} (#{orchestrator.model})")
        @output.output("Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit.")
        @output.output("(Ctrl-C during processing aborts operation)")
        @output.output("Type /help for available commands")
        @output.output("=" * 60)
      end

      def print_goodbye
        @output.output("\n\nGoodbye!")
      end

      def build_redaction_index(original_messages, redacted_messages)
        # Collect IDs of messages that were redacted or removed
        redacted_ids = []

        original_messages.each do |msg|
          next unless msg['id']

          # Check if this message was removed entirely
          redacted_version = redacted_messages.find { |m| m['id'] == msg['id'] }

          if redacted_version.nil?
            # Message was completely removed
            redacted_ids << msg['id']
          elsif message_was_redacted?(msg, redacted_version)
            # Message was redacted but still present
            redacted_ids << msg['id']
          end
        end

        return nil if redacted_ids.empty?

        # Format IDs as ranges for compact display
        ranges = format_id_ranges(redacted_ids.sort)

        # Build concise index message
        "[Messages #{ranges} redacted - use database_message(id) to retrieve if needed]"
      end

      def message_was_redacted?(original, redacted)
        # Check if content/data was redacted
        return true if original['tool_result'] && redacted['tool_result'] && redacted['tool_result']['result'] == { 'redacted' => true }
        return true if original['tool_calls'] && !redacted['tool_calls']  # Tool calls were removed
        return true if original['content'] && !redacted['content']
        false
      end

      def format_id_ranges(ids)
        return "" if ids.empty?

        ranges = []
        range_start = ids.first
        range_end = ids.first

        ids.each_cons(2) do |current, nxt|
          if nxt == current + 1
            range_end = nxt
          else
            ranges << (range_start == range_end ? "#{range_start}" : "#{range_start}-#{range_end}")
            range_start = nxt
            range_end = nxt
          end
        end

        # Add final range
        ranges << (range_start == range_end ? "#{range_start}" : "#{range_start}-#{range_end}")

        ranges.join(", ")
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

          thread = Thread.new(conv_id, hist, status, status_mtx, app, @summarizer) do |current_conversation_id, history, summarizer_status, status_mutex, application, summarizer|
            begin
              summarize_conversations(
                current_conversation_id: current_conversation_id,
                history: history,
                summarizer_status: summarizer_status,
                status_mutex: status_mutex,
                application: application,
                summarizer: summarizer
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

      def summarize_conversations(current_conversation_id:, history:, summarizer_status:, status_mutex:, application:, summarizer:)
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
                  model: summarizer.model,
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
            redacted_messages = redact_old_tool_results(messages)

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
                  model: summarizer.model,
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
