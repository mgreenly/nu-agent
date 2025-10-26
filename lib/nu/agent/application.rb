# frozen_string_literal: true

module Nu
  module Agent
    class Application
      attr_reader :orchestrator, :history, :formatter, :conversation_id, :session_start_time, :summarizer_status,
                  :man_indexer_status, :status_mutex, :verbosity, :console, :debug
      attr_accessor :active_threads

      def initialize(options:)
        $stdout.sync = true
        @session_start_time = Time.now
        @options = options
        @user_actor = ENV["USER"] || "user"
        @shutdown = false
        @critical_sections = 0
        @critical_mutex = Mutex.new
        @operation_mutex = Mutex.new
        @history = History.new

        # Load or initialize model configurations
        orchestrator_model = @history.get_config("model_orchestrator")
        spellchecker_model = @history.get_config("model_spellchecker")
        summarizer_model = @history.get_config("model_summarizer")

        # Handle --reset-model flag
        if @options.reset_model
          @history.set_config("model_orchestrator", @options.reset_model)
          @history.set_config("model_spellchecker", @options.reset_model)
          @history.set_config("model_summarizer", @options.reset_model)
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
        @debug = @history.get_config("debug", default: "false") == "true"
        @debug = true if @options.debug # Command line option overrides database setting

        # Initialize ConsoleIO (new unified console system)
        @console = ConsoleIO.new(db_history: @history, debug: @debug)

        # Load verbosity
        @verbosity = @history.get_config("verbosity", default: "0").to_i

        # Old TUI system removed - now using ConsoleIO exclusively
        @redact = @history.get_config("redaction", default: "true") == "true"
        @summarizer_enabled = @history.get_config("summarizer_enabled", default: "true") == "true"
        @spell_check_enabled = @history.get_config("spell_check_enabled", default: "true") == "true"
        @conversation_id = @history.create_conversation
        @formatter = Formatter.new(
          history: @history,
          session_start_time: @session_start_time,
          conversation_id: @conversation_id,
          orchestrator: @orchestrator,
          debug: @debug,
          console: @console, # ConsoleIO for all output
          application: self
        )
        @active_threads = []
        @summarizer_status = {
          "running" => false,
          "total" => 0,
          "completed" => 0,
          "failed" => 0,
          "current_conversation_id" => nil,
          "last_summary" => nil,
          "spend" => 0.0
        }
        @man_indexer_status = {
          "running" => false,
          "total" => 0,
          "completed" => 0,
          "failed" => 0,
          "skipped" => 0,
          "current_batch" => nil,
          "session_spend" => 0.0,
          "session_tokens" => 0
        }
        @status_mutex = Mutex.new

        # Initialize index_man_enabled to false on startup
        @history.set_config("index_man_enabled", "false")

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

        # Close TUI before waiting for threads
        @tui&.close

        # Wait for any critical sections (database writes) to complete
        timeout = 5.0
        start_time = Time.now
        sleep 0.1 while in_critical_section? && (Time.now - start_time) < timeout

        # Wait for any active threads to complete (they should exit quickly)
        active_threads.each(&:join)
        history&.close
      end

      def process_input(input)
        # Handle commands
        return handle_command(input) if input.start_with?("/")

        # Capture exchange start time for elapsed time calculation
        @formatter.exchange_start_time = Time.now

        # Start spinner
        @console.show_spinner("Thinking...")

        thread = nil
        workers_incremented = false

        begin
          # Increment workers BEFORE spawning thread
          history.increment_workers
          workers_incremented = true

          # Capture values to pass into thread under mutex
          thread = @operation_mutex.synchronize do
            conv_id = conversation_id
            hist = history
            cli = orchestrator
            session_start = session_start_time
            user_in = input
            formatter
            app = self

            # Display thread start event
            formatter.display_thread_event("Orchestrator", "Starting")

            # Spawn orchestrator thread with raw user input
            Thread.new(conv_id, hist, cli, session_start, user_in,
                       app) do |conversation_id, history, client, session_start_time, user_input, application|
              chat_loop(
                conversation_id: conversation_id,
                history: history,
                client: client,
                session_start_time: session_start_time,
                user_input: user_input,
                application: application
              )
            ensure
              history.decrement_workers
            end
          end

          active_threads << thread

          # Wait for completion and display
          formatter.wait_for_completion(conversation_id: conversation_id)

          # Display thread finished event (after all output is shown)
          formatter.display_thread_event("Orchestrator", "Finished")
        rescue Interrupt
          # Ctrl-C pressed - kill thread and return to prompt
          # Transaction will rollback automatically - no exchange will be saved
          @console.hide_spinner
          output_line("(Ctrl-C) Operation aborted by user.", type: :debug)

          # Kill all active threads (orchestrator, summarizer, etc.)
          active_threads.each do |t|
            t.kill if t.alive?
          end
          active_threads.clear

          # Clean up worker count if needed
          if thread&.alive?
            history.decrement_workers
          elsif workers_incremented
            # Workers were incremented but thread wasn't created yet
            history.decrement_workers
          end
        ensure
          # Always stop the spinner
          @console.hide_spinner
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
          @critical_sections.positive?
        end
      end

      # Helper to output text via ConsoleIO
      def output_line(text, type: :normal)
        case type
        when :debug
          # Only output debug messages when debug mode is enabled
          @console.puts("\e[90m#{text}\e[0m") if @debug
        when :error
          @console.puts("\e[31m#{text}\e[0m")
        else
          @console.puts(text)
        end
      end

      # Helper to output multiple lines via ConsoleIO
      def output_lines(*lines, type: :normal)
        lines.each do |line|
          output_line(line, type: type)
        end
      end

      def build_context_document(user_query:, tool_registry:, redacted_message_ranges: nil, conversation_id: nil)
        builder = DocumentBuilder.new

        # Context section (RAG - Retrieval Augmented Generation)
        # Multiple RAG sub-processes will be added here in the future
        rag_content = []

        # RAG sub-process 1: Redacted message ranges
        if redacted_message_ranges && !redacted_message_ranges.empty?
          rag_content << "Redacted messages: #{redacted_message_ranges}"
        end

        # RAG sub-process 2: Spell checking (if enabled)
        if @spell_check_enabled && @spellchecker
          spell_checker = SpellChecker.new(
            history: history,
            conversation_id: conversation_id,
            client: @spellchecker
          )
          corrected_query = spell_checker.check_spelling(user_query)

          rag_content << "The user said '#{user_query}' but means '#{corrected_query}'" if corrected_query != user_query
        end

        # If no RAG content was generated, indicate that
        rag_content << "No Augmented Information Generated" if rag_content.empty?

        builder.add_section("Context", rag_content.join("\n\n"))

        # Available Tools section
        tool_names = tool_registry.available.map(&:name)
        tools_list = tool_names.join(", ")
        builder.add_section("Available Tools", tools_list)

        # User Query section (final section - ends the document)
        builder.add_section("User Query", user_query)

        builder.build
      end

      def tool_calling_loop(messages:, tools:, client:, history:, conversation_id:, exchange_id:, tool_registry:,
                            application:)
        # Inner loop that handles tool calling until we get a final response
        # All tool calls and intermediate responses are saved as redacted

        metrics = {
          tokens_input: 0,
          tokens_output: 0,
          spend: 0.0,
          message_count: 0,
          tool_call_count: 0
        }

        loop do
          # Send request to LLM
          response = client.send_message(messages: messages, tools: tools)

          # Check for errors first
          if response["error"]
            # Save error message (unredacted so user can see it)
            history.add_message(
              conversation_id: conversation_id,
              exchange_id: exchange_id,
              actor: "api_error",
              role: "assistant",
              content: response["content"],
              model: response["model"],
              error: response["error"],
              redacted: false
            )
            @formatter.display_message_created(actor: "api_error", role: "assistant", content: response["content"])
            return { error: true, response: response, metrics: metrics }
          end

          # Update metrics (after error check, with nil protection)
          metrics[:tokens_input] = [metrics[:tokens_input], response["tokens"]["input"] || 0].max
          metrics[:tokens_output] += response["tokens"]["output"] || 0
          metrics[:spend] += response["spend"] || 0.0
          metrics[:message_count] += 1

          # Check for tool calls
          if response["tool_calls"]
            # Save assistant message with tool calls (REDACTED)
            history.add_message(
              conversation_id: conversation_id,
              exchange_id: exchange_id,
              actor: "orchestrator",
              role: "assistant",
              content: response["content"],
              model: response["model"],
              tokens_input: response["tokens"]["input"] || 0,
              tokens_output: response["tokens"]["output"] || 0,
              spend: response["spend"] || 0.0,
              tool_calls: response["tool_calls"],
              redacted: true # Tool calls are redacted
            )
            @formatter.display_message_created(
              actor: "orchestrator",
              role: "assistant",
              content: response["content"],
              tool_calls: response["tool_calls"],
              redacted: true
            )

            # Display content as normal output if present (LLM explaining what it's doing)
            if response["content"] && !response["content"].strip.empty?
              @console.hide_spinner
              output_line(response["content"])
              @console.show_spinner("Thinking...")
            end

            metrics[:tool_call_count] += response["tool_calls"].length

            # Add assistant message to in-memory messages
            messages << {
              "role" => "assistant",
              "content" => response["content"],
              "tool_calls" => response["tool_calls"]
            }

            # Execute each tool call
            response["tool_calls"].each do |tool_call|
              result = tool_registry.execute(
                name: tool_call["name"],
                arguments: tool_call["arguments"],
                history: history,
                context: {
                  "conversation_id" => conversation_id,
                  "model" => client.model,
                  "application" => application
                }
              )

              # Save tool result (REDACTED)
              tool_result_data = {
                "name" => tool_call["name"],
                "result" => result
              }
              history.add_message(
                conversation_id: conversation_id,
                exchange_id: exchange_id,
                actor: "orchestrator",
                role: "tool",
                content: "",
                tool_call_id: tool_call["id"],
                tool_result: tool_result_data,
                redacted: true # Tool results are redacted
              )
              @formatter.display_message_created(
                actor: "orchestrator",
                role: "tool",
                tool_result: tool_result_data,
                redacted: true
              )

              # Add tool result to in-memory messages (must match format expected by clients)
              messages << {
                "role" => "tool",
                "tool_call_id" => tool_call["id"],
                "content" => result.is_a?(Hash) ? result.to_json : result.to_s,
                "tool_result" => {
                  "name" => tool_call["name"],
                  "result" => result
                }
              }
            end

            # Continue loop to get next LLM response
          else
            # No tool calls - this is the final response
            # Check if content is empty (LLM sent empty response)
            if response["content"].nil? || response["content"].strip.empty?
              # Log this as a warning but continue
              # The response will be saved and displayed (or not displayed if empty)
            end
            # Return it (will be saved as unredacted by caller)
            return { error: false, response: response, metrics: metrics }
          end
        end
      end

      def chat_loop(conversation_id:, history:, client:, session_start_time:, user_input:, application:)
        # Orchestrator owns the entire exchange - wrap everything in a transaction
        # Either the exchange completes successfully or nothing is saved
        history.transaction do
          tool_registry = ToolRegistry.new

          # Create exchange and add user message (atomic with rest of exchange)
          exchange_id = history.create_exchange(
            conversation_id: conversation_id,
            user_message: user_input
          )

          history.add_message(
            conversation_id: conversation_id,
            exchange_id: exchange_id,
            actor: @user_actor,
            role: "user",
            content: user_input
          )
          @formatter.display_message_created(actor: @user_actor, role: "user", content: user_input)

          # Get conversation history (only unredacted messages from previous exchanges)
          all_messages = history.messages(conversation_id: conversation_id, since: session_start_time)

          # Get redacted message IDs and format as ranges
          redacted_message_ranges = nil
          if @redact
            redacted_ids = all_messages.select { |m| m["redacted"] }.map { |m| m["id"] }.compact
            redacted_message_ranges = format_id_ranges(redacted_ids.sort) if redacted_ids.any?
          end

          # Filter to only unredacted messages from PREVIOUS exchanges (exclude current exchange)
          history_messages = all_messages.reject { |m| m["redacted"] || m["exchange_id"] == exchange_id }

          # User query is the input we just received
          user_query = user_input

          # Build context document (markdown) with RAG, tools, and user query
          markdown_document = build_context_document(
            user_query: user_query,
            tool_registry: tool_registry,
            redacted_message_ranges: redacted_message_ranges,
            conversation_id: conversation_id
          )

          # Build initial messages array: history + markdown document
          messages = history_messages.dup
          messages << {
            "role" => "user",
            "content" => markdown_document
          }

          # Get tools formatted for this client
          tools = client.format_tools(tool_registry)

          # Display LLM request (verbosity level 3+)
          @formatter.display_llm_request(messages, tools, markdown_document)

          # Call inner tool calling loop
          result = tool_calling_loop(
            messages: messages,
            tools: tools,
            client: client,
            history: history,
            conversation_id: conversation_id,
            exchange_id: exchange_id,
            tool_registry: tool_registry,
            application: application
          )

          # Handle result
          if result[:error]
            # Mark exchange as failed
            history.update_exchange(
              exchange_id: exchange_id,
              updates: {
                status: "failed",
                error: result[:response]["error"].to_json,
                completed_at: Time.now
              }.merge(result[:metrics])
            )
          else
            # Save final assistant response (unredacted)
            final_response = result[:response]
            history.add_message(
              conversation_id: conversation_id,
              exchange_id: exchange_id,
              actor: "orchestrator",
              role: "assistant",
              content: final_response["content"],
              model: final_response["model"],
              tokens_input: final_response["tokens"]["input"] || 0,
              tokens_output: final_response["tokens"]["output"] || 0,
              spend: final_response["spend"] || 0.0,
              redacted: false # Final response is unredacted
            )
            @formatter.display_message_created(
              actor: "orchestrator",
              role: "assistant",
              content: final_response["content"],
              redacted: false
            )

            # Update metrics to include final response (with nil protection)
            metrics = result[:metrics]
            metrics[:tokens_input] = [metrics[:tokens_input], final_response["tokens"]["input"] || 0].max
            metrics[:tokens_output] += final_response["tokens"]["output"] || 0
            metrics[:spend] += final_response["spend"] || 0.0
            metrics[:message_count] += 1

            # Complete the exchange
            history.complete_exchange(
              exchange_id: exchange_id,
              assistant_message: final_response["content"],
              metrics: metrics
            )
          end
        end
        # Transaction commits here on success, rolls back on exception
      end

      def repl
        loop do
          # Add blank line before prompt for better readability
          @console.puts("")

          begin
            input = @console.readline("> ")
          rescue Interrupt
            # Ctrl-C while waiting for input - exit program
            break
          end

          break if input.nil? # Ctrl+D

          input = input.strip

          # Skip empty input
          next if input.empty?

          result = process_input(input)
          break if result == :exit
        end
      end

      def setup_readline
        # Set up tab completion
        commands = ["/clear", "/debug", "/exit", "/fix", "/help", "/index-man", "/info", "/migrate-exchanges",
                    "/model", "/models", "/redaction", "/reset", "/spellcheck", "/summarizer", "/tools", "/verbosity"]
        all_models = ClientFactory.available_models.values.flatten

        Readline.completion_proc = proc do |str|
          # Check if we're completing after '/model '
          line = Readline.line_buffer
          if line.start_with?("/model ")
            # Complete model names
            prefix_match = line.match(%r{^/model\s+(.*)})
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
        history_file = File.join(Dir.home, ".nu_agent_history")
        return unless File.exist?(history_file)

        File.readlines(history_file).each do |line|
          Readline::HISTORY.push(line.chomp)
        end
      end

      def save_history
        history_file = File.join(Dir.home, ".nu_agent_history")
        File.open(history_file, "w") do |f|
          Readline::HISTORY.to_a.last(1000).each { |line| f.puts(line) }
        end
      rescue StandardError
        # Silently ignore history save errors
      end

      def handle_command(input)
        # Handle /model command with subcommands
        parts = input.split
        if parts.first&.downcase == "/model"

          # /model without arguments - show current models
          if parts.length == 1
            output_line("Current Models:", type: :debug)
            output_line("  Orchestrator:  #{@orchestrator.model}", type: :debug)
            output_line("  Spellchecker:  #{@spellchecker.model}", type: :debug)
            output_line("  Summarizer:    #{@summarizer.model}", type: :debug)
            return :continue
          end

          # /model <subcommand> <name>
          if parts.length < 3
            output_line("Usage:", type: :debug)
            output_line("  /model                        Show current models", type: :debug)
            output_line("  /model orchestrator <name>    Set orchestrator model", type: :debug)
            output_line("  /model spellchecker <name>    Set spellchecker model", type: :debug)
            output_line("  /model summarizer <name>      Set summarizer model", type: :debug)
            output_line("Example: /model orchestrator gpt-5", type: :debug)
            output_line("Run /models to see available models", type: :debug)
            return :continue
          end

          subcommand = parts[1].strip.downcase
          new_model_name = parts[2].strip

          case subcommand
          when "orchestrator"
            # Switch model under mutex (blocks if thread is running)
            @operation_mutex.synchronize do
              # Wait for active threads to complete
              unless active_threads.empty?
                still_running = active_threads.any? do |thread|
                  !thread.join(0.05)
                end

                if still_running
                  output_line("Waiting for current operation to complete...", type: :debug)
                  active_threads.each(&:join)
                end
              end

              # Try to create new client
              begin
                new_client = ClientFactory.create(new_model_name)
              rescue Error => e
                output_line("Error: #{e.message}", type: :error)
                return :continue
              end

              # Switch both orchestrator and formatter
              @orchestrator = new_client
              @formatter.orchestrator = new_client
              @history.set_config("model_orchestrator", new_model_name)

              output_line("Switched orchestrator to: #{@orchestrator.name} (#{@orchestrator.model})", type: :debug)
            end

          when "spellchecker"
            begin
              # Create new client
              new_client = ClientFactory.create(new_model_name)
              @spellchecker = new_client
              @history.set_config("model_spellchecker", new_model_name)
              output_line("Switched spellchecker to: #{new_model_name}", type: :debug)
            rescue Error => e
              output_line("Error: #{e.message}", type: :error)
            end

          when "summarizer"
            begin
              # Create new client
              new_client = ClientFactory.create(new_model_name)
              @summarizer = new_client
              @history.set_config("model_summarizer", new_model_name)
              output_line("Switched summarizer to: #{new_model_name}", type: :debug)
              output_line("Note: Change takes effect at the start of the next session (/reset)", type: :debug)
            rescue Error => e
              output_line("Error: #{e.message}", type: :error)
            end

          else
            output_line("Unknown subcommand: #{subcommand}", type: :debug)
            output_line("Valid subcommands: orchestrator, spellchecker, summarizer", type: :debug)
          end

          return :continue
        end

        # Handle /redaction [on/off] command
        if input.downcase.start_with?("/redaction")
          parts = input.split(" ", 2)
          if parts.length < 2 || parts[1].strip.empty?
            output_line("Usage: /redaction <on|off>", type: :debug)
            output_line("Current: redaction=#{@redact ? 'on' : 'off'}", type: :debug)
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == "on"
            @redact = true
            history.set_config("redaction", "true")
            output_line("redaction=on", type: :debug)
          elsif setting == "off"
            @redact = false
            history.set_config("redaction", "false")
            output_line("redaction=off", type: :debug)
          else
            output_line("Invalid option. Use: /redaction <on|off>", type: :debug)
          end

          return :continue
        end

        # Handle /summarizer [on/off] command
        if input.downcase.start_with?("/summarizer")
          parts = input.split(" ", 2)
          if parts.length < 2 || parts[1].strip.empty?
            output_line("Usage: /summarizer <on|off>", type: :debug)
            output_line("Current: summarizer=#{@summarizer_enabled ? 'on' : 'off'}", type: :debug)
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == "on"
            @summarizer_enabled = true
            history.set_config("summarizer_enabled", "true")
            output_line("summarizer=on", type: :debug)
            output_line("Summarizer will start on next /reset", type: :debug)
          elsif setting == "off"
            @summarizer_enabled = false
            history.set_config("summarizer_enabled", "false")
            output_line("summarizer=off", type: :debug)
          else
            output_line("Invalid option. Use: /summarizer <on|off>", type: :debug)
          end

          return :continue
        end

        # Handle /spellcheck [on/off] command
        if input.downcase.start_with?("/spellcheck")
          parts = input.split(" ", 2)
          if parts.length < 2 || parts[1].strip.empty?
            output_line("Usage: /spellcheck <on|off>", type: :debug)
            output_line("Current: spellcheck=#{@spell_check_enabled ? 'on' : 'off'}", type: :debug)
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == "on"
            @spell_check_enabled = true
            history.set_config("spell_check_enabled", "true")
            output_line("spellcheck=on", type: :debug)
          elsif setting == "off"
            @spell_check_enabled = false
            history.set_config("spell_check_enabled", "false")
            output_line("spellcheck=off", type: :debug)
          else
            output_line("Invalid option. Use: /spellcheck <on|off>", type: :debug)
          end

          return :continue
        end

        # Handle /index-man [on|off|reset] command
        if input.downcase.start_with?("/index-man")
          parts = input.split(" ", 2)
          if parts.length < 2 || parts[1].strip.empty?
            output_line("Usage: /index-man <on|off|reset>", type: :debug)
            enabled = history.get_config("index_man_enabled") == "true"
            output_line("Current: index-man=#{enabled ? 'on' : 'off'}", type: :debug)

            # Show status if available
            @status_mutex.synchronize do
              status = @man_indexer_status
              if status["running"]
                output_line("Status: running (#{status['completed']}/#{status['total']} man pages)", type: :debug)
                output_line("Failed: #{status['failed']}, Skipped: #{status['skipped']}", type: :debug)
                output_line("Session spend: $#{'%.6f' % status['session_spend']}", type: :debug)
              elsif status["total"].positive?
                output_line("Status: completed (#{status['completed']}/#{status['total']} man pages)", type: :debug)
                output_line("Failed: #{status['failed']}, Skipped: #{status['skipped']}", type: :debug)
                output_line("Session spend: $#{'%.6f' % status['session_spend']}", type: :debug)
              end
            end

            return :continue
          end

          setting = parts[1].strip.downcase
          case setting
          when "on"
            history.set_config("index_man_enabled", "true")
            output_line("index-man=on", type: :debug)
            output_line("Starting man page indexer...", type: :debug)

            # Start the indexer worker
            start_man_indexer_worker

            # Show initial status
            sleep(0.5) # Give it a moment to start
            @status_mutex.synchronize do
              status = @man_indexer_status
              output_line("Indexing #{status['total']} man pages...", type: :debug)
              output_line("This will take approximately #{(status['total'] / 10.0 / 60.0).ceil} minutes", type: :debug)
            end

          when "off"
            history.set_config("index_man_enabled", "false")
            output_line("index-man=off", type: :debug)
            output_line("Indexer will stop after current batch completes", type: :debug)

            # Show final status
            @status_mutex.synchronize do
              status = @man_indexer_status
              if status["completed"].positive?
                output_line("Indexed: #{status['completed']}/#{status['total']} man pages", type: :debug)
                output_line("Failed: #{status['failed']}, Skipped: #{status['skipped']}", type: :debug)
                output_line("Session spend: $#{'%.6f' % status['session_spend']}", type: :debug)
              end
            end
          when "reset"
            # Stop indexing if running
            if history.get_config("index_man_enabled") == "true"
              history.set_config("index_man_enabled", "false")
              output_line("Stopping indexer before reset...", type: :debug)
              sleep(1) # Give worker time to stop
            end

            # Get count before clearing
            stats = history.embedding_stats(kind: "man_page")
            count = stats.find { |s| s["kind"] == "man_page" }&.fetch("count", 0) || 0

            # Clear all man_page embeddings
            history.clear_embeddings(kind: "man_page")

            # Reset status counters
            @status_mutex.synchronize do
              @man_indexer_status["total"] = 0
              @man_indexer_status["completed"] = 0
              @man_indexer_status["failed"] = 0
              @man_indexer_status["skipped"] = 0
              @man_indexer_status["session_spend"] = 0.0
              @man_indexer_status["session_tokens"] = 0
            end

            output_line("Reset complete: Cleared #{count} man page embeddings", type: :debug)
          else
            output_line("Invalid option. Use: /index-man <on|off|reset>", type: :debug)
          end

          return :continue
        end

        # Handle /debug [on/off] command
        if input.downcase.start_with?("/debug")
          parts = input.split(" ", 2)
          if parts.length < 2 || parts[1].strip.empty?
            @console.puts("\e[90mUsage: /debug <on|off>\e[0m")
            @console.puts("\e[90mCurrent: debug=#{@debug ? 'on' : 'off'}\e[0m")
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == "on"
            @debug = true
            @formatter.debug = true
            history.set_config("debug", "true")
            @console.puts("\e[90mdebug=on\e[0m")
          elsif setting == "off"
            @debug = false
            @formatter.debug = false
            history.set_config("debug", "false")
            @console.puts("\e[90mdebug=off\e[0m")
          else
            @console.puts("\e[90mInvalid option. Use: /debug <on|off>\e[0m")
          end

          return :continue
        end

        # Handle /verbosity [NUM] command
        if input.downcase.start_with?("/verbosity")
          parts = input.split(" ", 2)
          if parts.length < 2 || parts[1].strip.empty?
            @console.puts("\e[90mUsage: /verbosity <number>\e[0m")
            @console.puts("\e[90mCurrent: verbosity=#{@verbosity}\e[0m")
            return :continue
          end

          value = parts[1].strip
          if value =~ /^\d+$/
            @verbosity = value.to_i
            history.set_config("verbosity", value)
            @console.puts("\e[90mverbosity=#{@verbosity}\e[0m")
          else
            @console.puts("\e[90mInvalid option. Use: /verbosity <number>\e[0m")
          end

          return :continue
        end

        case input.downcase
        when "/exit"
          :exit
        when "/clear"
          if @tui&.active
            @tui.clear_output
          else
            system("clear")
          end
          :continue
        when "/tools"
          print_tools
          :continue
        when "/reset"
          if @tui&.active
            @tui.clear_output
          else
            system("clear")
          end
          @conversation_id = history.create_conversation
          @session_start_time = Time.now
          formatter.reset_session(conversation_id: @conversation_id)
          output_line("Conversation reset", type: :debug)

          # Start background summarization worker
          start_summarization_worker

          :continue
        when "/fix"
          run_fix
          :continue
        when "/migrate-exchanges"
          run_migrate_exchanges
          :continue
        when "/info"
          print_info
          :continue
        when "/models"
          print_models
          :continue
        when "/help"
          print_help
          :continue
        else
          output_line("Unknown command: #{input}", type: :debug)
          :continue
        end
      end

      def print_help
        output_lines(
          "Available commands:",
          "  /clear                         - Clear the screen",
          "  /debug <on|off>                - Enable/disable debug mode (show/hide tool calls and results)",
          "  /exit                          - Exit the REPL",
          "  /fix                           - Scan and fix database corruption issues",
          "  /help                          - Show this help message",
          "  /index-man <on|off|reset>      - Enable/disable background man page indexing, or reset database",
          "  /info                          - Show current session information",
          "  /migrate-exchanges             - Create exchanges from existing messages (one-time migration)",
          "  /model orchestrator <name>     - Switch orchestrator model",
          "  /model spellchecker <name>     - Switch spellchecker model",
          "  /model summarizer <name>       - Switch summarizer model",
          "  /models                        - List available models",
          "  /redaction <on|off>            - Enable/disable redaction of tool results in context",
          "  /verbosity <number>            - Set verbosity level for debug output (default: 0)",
          "                                   - Level 0: Thread lifecycle events + tool names only",
          "                                   - Level 1: Level 0 + truncated tool call/result params (30 chars)",
          "                                   - Level 2: Level 1 + message creation notifications",
          "                                   - Level 3: Level 2 + message role/actor + truncated content/params (30 chars)",
          "                                   - Level 4: Level 3 + full tool params + messages sent to LLM",
          "                                   - Level 5: Level 4 + tools array",
          "                                   - Level 6: Level 5 + longer message content previews (100 chars)",
          "  /reset                         - Start a new conversation",
          "  /spellcheck <on|off>           - Enable/disable automatic spell checking of user input",
          "  /summarizer <on|off>           - Enable/disable background conversation summarization",
          "  /tools                         - List available tools",
          type: :debug
        )
      end

      def run_fix
        output_line("Scanning database for corruption...", type: :debug)

        corrupted = history.find_corrupted_messages

        if corrupted.empty?
          output_line("✓ No corruption found", type: :debug)
          return
        end

        output_line("Found #{corrupted.length} corrupted message(s):", type: :debug)
        corrupted.each do |msg|
          output_line("  • Message #{msg['id']}: #{msg['tool_name']} with redacted arguments (#{msg['created_at']})", type: :debug)
        end

        if @tui&.active
          response = @tui.readline("Delete these messages? [y/N] ").chomp.downcase
        else
          print "\nDelete these messages? [y/N] "
          response = gets.chomp.downcase
        end

        if response == "y"
          ids = corrupted.map { |m| m["id"] }
          count = history.fix_corrupted_messages(ids)
          output_line("✓ Deleted #{count} corrupted message(s)", type: :debug)
        else
          output_line("Skipped", type: :debug)
        end
      end

      def run_migrate_exchanges
        output_line("This will analyze all messages and group them into exchanges.", type: :debug)
        output_line("Existing exchanges will NOT be affected.", type: :debug)

        if @tui&.active
          response = @tui.readline("Continue with migration? [y/N] ").chomp.downcase
        else
          print "Continue with migration? [y/N] "
          response = gets.chomp.downcase
        end

        return unless response == "y"

        output_line("Migrating exchanges...", type: :debug)

        start_time = Time.now
        stats = history.migrate_exchanges
        elapsed = Time.now - start_time

        output_line("Migration complete!", type: :debug)
        output_line("  Conversations processed: #{stats[:conversations]}", type: :debug)
        output_line("  Exchanges created: #{stats[:exchanges_created]}", type: :debug)
        output_line("  Messages updated: #{stats[:messages_updated]}", type: :debug)
        output_line("  Time elapsed: #{'%.2f' % elapsed}s", type: :debug)
      end

      def print_info
        output_line("Version:       #{Nu::Agent::VERSION}", type: :debug)

        # Models section
        output_line("Models:", type: :debug)
        output_line("  Orchestrator:  #{@orchestrator.model}", type: :debug)
        output_line("  Spellchecker:  #{@spellchecker.model}", type: :debug)
        output_line("  Summarizer:    #{@summarizer.model}", type: :debug)

        output_line("Debug mode:    #{@debug}", type: :debug)
        output_line("Verbosity:     #{@verbosity}", type: :debug)
        output_line("Redaction:     #{@redact ? 'on' : 'off'}", type: :debug)
        output_line("Summarizer:    #{@summarizer_enabled ? 'on' : 'off'}", type: :debug)

        # Show summarizer status if enabled
        if @summarizer_enabled
          @status_mutex.synchronize do
            status = @summarizer_status
            if status["running"]
              output_line("  Status:      running (#{status['completed']}/#{status['total']} conversations)", type: :debug)
              output_line("  Spend:       $#{'%.6f' % status['spend']}", type: :debug) if status["spend"].positive?
            elsif status["total"].positive?
              output_line("  Status:      completed (#{status['completed']}/#{status['total']} conversations, #{status['failed']} failed)", type: :debug)
              output_line("  Spend:       $#{'%.6f' % status['spend']}", type: :debug) if status["spend"].positive?
            else
              output_line("  Status:      idle", type: :debug)
            end
          end
        end

        output_line("Spellcheck:    #{@spell_check_enabled ? 'on' : 'off'}", type: :debug)
        output_line("Database:      #{File.expand_path(history.db_path)}", type: :debug)
      end

      def print_models
        models = ClientFactory.display_models

        # Get defaults from each client
        anthropic_default = Nu::Agent::Clients::Anthropic::DEFAULT_MODEL
        google_default = Nu::Agent::Clients::Google::DEFAULT_MODEL
        openai_default = Nu::Agent::Clients::OpenAI::DEFAULT_MODEL
        xai_default = Nu::Agent::Clients::XAI::DEFAULT_MODEL

        # Mark defaults with asterisk
        anthropic_list = models[:anthropic].map { |m| m == anthropic_default ? "#{m}*" : m }.join(", ")
        google_list = models[:google].map { |m| m == google_default ? "#{m}*" : m }.join(", ")
        openai_list = models[:openai].map { |m| m == openai_default ? "#{m}*" : m }.join(", ")
        xai_list = models[:xai].map { |m| m == xai_default ? "#{m}*" : m }.join(", ")

        output_line("Available Models (* = default):", type: :debug)
        output_line("  Anthropic: #{anthropic_list}", type: :debug)
        output_line("  Google:    #{google_list}", type: :debug)
        output_line("  OpenAI:    #{openai_list}", type: :debug)
        output_line("  X.AI:      #{xai_list}", type: :debug)
      end

      def print_tools
        tool_registry = ToolRegistry.new

        output_line("Available Tools:", type: :debug)
        tool_registry.all.each do |tool|
          # Get first sentence of description
          desc = tool.description.split(/\.\s+/).first || tool.description
          desc = desc.strip
          desc += "." unless desc.end_with?(".")

          # Check if tool has credentials (if applicable)
          desc += " (disabled)" if tool.respond_to?(:available?) && !tool.available?

          output_line("  #{tool.name.ljust(25)} - #{desc}", type: :debug)
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
        print "\033[2J\033[H" unless @tui&.active
        output_lines(
          "Nu Agent REPL",
          "Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit.",
          "(Ctrl-C during processing aborts operation)",
          "Type /help for available commands",
          "=" * 60
        )
      end

      def print_goodbye
        output_line("Goodbye!", type: :debug)
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
            ranges << (range_start == range_end ? range_start.to_s : "#{range_start}-#{range_end}")
            range_start = nxt
            range_end = nxt
          end
        end

        # Add final range
        ranges << (range_start == range_end ? range_start.to_s : "#{range_start}-#{range_end}")

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
            "#{seconds / 60}m ago"
          elsif seconds < 86_400
            "#{seconds / 3600}h ago"
          else
            "#{seconds / 86_400}d ago"
          end
        rescue StandardError
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

          thread = Thread.new(conv_id, hist, status, status_mtx, app,
                              @summarizer) do |current_conversation_id, history, summarizer_status, status_mutex, application, summarizer|
            summarize_conversations(
              current_conversation_id: current_conversation_id,
              history: history,
              summarizer_status: summarizer_status,
              status_mutex: status_mutex,
              application: application,
              summarizer: summarizer
            )
          rescue StandardError
            status_mutex.synchronize do
              summarizer_status["running"] = false
            end
          end

          active_threads << thread
        end
      end

      def summarize_conversations(current_conversation_id:, history:, summarizer_status:, status_mutex:, application:,
                                  summarizer:)
        # Get conversations that need summarization
        conversations = history.get_unsummarized_conversations(exclude_id: current_conversation_id)

        return if conversations.empty?

        # Update status
        status_mutex.synchronize do
          summarizer_status["running"] = true
          summarizer_status["total"] = conversations.length
          summarizer_status["completed"] = 0
          summarizer_status["failed"] = 0
        end

        conversations.each do |conv|
          # Check for shutdown signal before processing each conversation
          break if application.instance_variable_get(:@shutdown)

          conv_id = conv["id"]

          # Update current conversation being processed
          status_mutex.synchronize do
            summarizer_status["current_conversation_id"] = conv_id
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
                summarizer_status["completed"] += 1
                summarizer_status["last_summary"] = "empty conversation"
              end

              next
            end

            # Filter to only unredacted messages (same as we do for context)
            unredacted_messages = messages.reject { |m| m["redacted"] }

            # Build prompt for summarization
            context = unredacted_messages.map do |msg|
              role = msg["role"] == "tool" ? "assistant" : msg["role"]
              content = msg["content"] || ""
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
                messages: [{ "role" => "user", "content" => summary_prompt }],
                tools: nil
              )
            end

            # Poll the thread, checking for shutdown every 100ms
            response = nil
            loop do
              if llm_thread.join(0.1) # Try to join with 100ms timeout
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

            if response["error"]
              status_mutex.synchronize do
                summarizer_status["failed"] += 1
              end
              next
            end

            summary = response["content"]&.strip
            cost = response["spend"] || 0.0

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
                summarizer_status["completed"] += 1
                summarizer_status["last_summary"] = summary
                summarizer_status["spend"] += cost
              end
            else
              status_mutex.synchronize do
                summarizer_status["failed"] += 1
              end
            end
          rescue StandardError
            status_mutex.synchronize do
              summarizer_status["failed"] += 1
            end
          end
        end

        # Mark as complete
        status_mutex.synchronize do
          summarizer_status["running"] = false
          summarizer_status["current_conversation_id"] = nil
        end
      end

      def start_man_indexer_worker
        # Capture values for thread
        @operation_mutex.synchronize do
          hist = history
          status = @man_indexer_status
          status_mtx = @status_mutex
          app = self

          thread = Thread.new(hist, status, status_mtx, app) do |history, indexer_status, status_mutex, application|
            index_man_pages(
              history: history,
              indexer_status: indexer_status,
              status_mutex: status_mutex,
              application: application
            )
          rescue StandardError => e
            application.output_line("[Man Indexer] Worker thread error: #{e.class}: #{e.message}", type: :error)
            if application.instance_variable_get(:@debug)
              e.backtrace.first(10).each do |line|
                application.output_line("  #{line}", type: :debug)
              end
            end
            status_mutex.synchronize do
              indexer_status["running"] = false
            end
          end

          active_threads << thread
        end
      end

      def index_man_pages(history:, indexer_status:, status_mutex:, application:)
        # Create OpenAI Embeddings client
        begin
          embeddings_client = Clients::OpenAIEmbeddings.new
        rescue StandardError => e
          application.output_line("[Man Indexer] ERROR: Failed to create OpenAI Embeddings client", type: :error)
          application.output_line("  #{e.message}", type: :error)
          application.output_line("Man page indexing requires OpenAI embeddings API access.", type: :error)
          application.output_line("Please ensure your OpenAI API key has access to text-embedding-3-small.",
                                  type: :error)
          status_mutex.synchronize { indexer_status["running"] = false }
          return
        end

        # Create man indexer with application for debug messages
        man_indexer = ManIndexer.new(
          history: history,
          embeddings_client: embeddings_client,
          application: application
        )

        loop do
          # Check for shutdown or disabled
          break if application.instance_variable_get(:@shutdown)
          break unless history.get_config("index_man_enabled") == "true"

          # Get all man pages from system
          all_man_pages = man_indexer.get_all_man_pages

          # Get already indexed man pages from DB
          indexed = history.get_indexed_sources(kind: "man_page")

          # Calculate exclusive set (not yet indexed)
          to_index = all_man_pages - indexed

          # Update total count
          status_mutex.synchronize do
            indexer_status["running"] = true
            indexer_status["total"] = all_man_pages.length
            indexer_status["completed"] = indexed.length
          end

          # Break if nothing left to index
          if to_index.empty?
            status_mutex.synchronize do
              indexer_status["running"] = false
            end
            break
          end

          # Process in batches of 10
          batch = to_index.take(10)

          # Update current batch
          status_mutex.synchronize do
            indexer_status["current_batch"] = batch
          end

          # Extract DESCRIPTION sections
          records = []
          batch.each do |source|
            # Check for shutdown before processing each man page
            break if application.instance_variable_get(:@shutdown)

            description = man_indexer.extract_description(source)

            if description.nil? || description.empty?
              # Skip this man page
              status_mutex.synchronize do
                indexer_status["skipped"] += 1
              end
              next
            end

            records << {
              source: source,
              content: description
            }
          end

          # Skip API call if no valid descriptions
          if records.empty?
            sleep(1)
            next
          end

          # Check for shutdown before expensive API call
          break if application.instance_variable_get(:@shutdown)

          # Call OpenAI embeddings API (batch request)
          begin
            contents = records.map { |r| r[:content] }
            response = embeddings_client.generate_embedding(contents)

            # Check for errors
            if response["error"]
              error_body = response["error"]["body"]
              if error_body && error_body["error"]
                error_msg = error_body["error"]["message"]
                error_code = error_body["error"]["code"]

                # Check for model access issues
                if error_code == "model_not_found" && error_msg.include?("text-embedding-3-small")
                  application.output_line(
                    "[Man Indexer] ERROR: OpenAI API key does not have access to text-embedding-3-small",
                    type: :error
                  )
                  application.output_line("  Please enable embeddings API access in your OpenAI project settings",
                                          type: :error)
                  application.output_line("  Visit: https://platform.openai.com/settings", type: :error)

                  # Stop indexing - no point continuing
                  status_mutex.synchronize { indexer_status["running"] = false }
                  break
                else
                  application.output_line("[Man Indexer] API Error: #{error_msg}", type: :debug)
                end
              end

              status_mutex.synchronize do
                indexer_status["failed"] += records.length
              end
              sleep(6) # Rate limiting
              next
            end

            # Get embeddings
            embeddings = response["embeddings"]

            # Add embeddings to records
            records.each_with_index do |record, i|
              record[:embedding] = embeddings[i]
            end

            # Store in database
            application.send(:enter_critical_section)
            begin
              history.store_embeddings(kind: "man_page", records: records)
            ensure
              application.send(:exit_critical_section)
            end

            # Update status
            status_mutex.synchronize do
              indexer_status["completed"] += records.length
              indexer_status["session_spend"] += response["spend"] || 0.0
              indexer_status["session_tokens"] += response["tokens"] || 0
            end
          rescue StandardError => e
            # On error, mark batch as failed and log the error
            status_mutex.synchronize do
              indexer_status["failed"] += records.length
            end

            # Log error using thread-safe output
            application.output_line("[Man Indexer] Error processing batch: #{e.class}: #{e.message}", type: :debug)
            if application.instance_variable_get(:@debug)
              e.backtrace.first(5).each do |line|
                application.output_line("  #{line}", type: :debug)
              end
            end
          end

          # Rate limiting: sleep to maintain 10 req/min (6 seconds between requests)
          sleep(6) unless application.instance_variable_get(:@shutdown)
        end

        # Mark as complete
        status_mutex.synchronize do
          indexer_status["running"] = false
          indexer_status["current_batch"] = nil
        end
      end
    end
  end
end
