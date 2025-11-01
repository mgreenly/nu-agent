# frozen_string_literal: true

module Nu
  module Agent
    class Application
      attr_accessor :orchestrator, :spellchecker, :summarizer, :debug, :redact,
                    :summarizer_enabled, :spell_check_enabled, :embedding_enabled, :conversation_id, :session_start_time
      attr_reader :history, :formatter, :status_mutex, :console, :operation_mutex, :worker_manager, :embedding_client,
                  :active_persona_system_prompt, :event_bus

      def active_threads
        @worker_manager&.active_threads || []
      end

      def summarizer_status
        @worker_manager&.summarizer_status
      end

      def exchange_summarizer_status
        @worker_manager&.exchange_summarizer_status
      end

      def embedding_status
        @worker_manager&.embedding_status
      end

      def initialize(options:)
        initialize_state(options)
        load_and_apply_configuration
        initialize_console_system
        initialize_status_tracking
        initialize_commands
        start_background_workers
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
        sleep 0.1 while in_critical_section? && (Time.now - start_time) < timeout

        # Wait for any active threads to complete (they should exit quickly)
        active_threads.each(&:join)
        history&.close
      end

      def process_input(input)
        @input_processor.process(input)
      end

      # Helper to output text via ConsoleIO
      def output_line(text, type: :normal)
        case type
        when :command
          # Command output - always visible, styled in gray
          @console.puts("\e[90m#{text}\e[0m")
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

      # Clear the screen
      def clear_screen
        system("clear")
      end

      # Reopen the database after closing it (e.g., for backup operations)
      # This re-initializes the History object and updates all dependent
      # components to reference the new history object
      def reopen_database
        @history = History.new

        # Update component references to use the new history object
        @console.instance_variable_set(:@db_history, @history)
        @formatter.instance_variable_set(:@history, @history)
        @worker_manager.instance_variable_set(:@history, @history)

        # Update worker instances to use the new history object
        worker_instances = @worker_manager.instance_variable_get(:@worker_instances)
        return unless worker_instances

        worker_instances.each_value do |worker|
          worker.instance_variable_set(:@history, @history) if worker.instance_variable_defined?(:@history)
        end
      end

      private

      # Check if running in CI environment
      # @return [Boolean] true if CI environment variable is set
      def ci_environment?
        ENV.fetch("CI", "false") == "true"
      end

      def initialize_state(options)
        $stdout.sync = true
        @session_start_time = Time.now
        @options = options
        @user_actor = ENV["USER"] || "user"
        @shutdown = false
        @critical_sections = 0
        @critical_mutex = Mutex.new
        @operation_mutex = Mutex.new
        @history = History.new
        @input_processor = InputProcessor.new(application: self, user_actor: @user_actor)
      end

      def load_and_apply_configuration
        config = ConfigurationLoader.load(history: @history, options: @options)
        @orchestrator = config.orchestrator
        @spellchecker = config.spellchecker
        @summarizer = config.summarizer
        @debug = config.debug
        @redact = config.redact
        @summarizer_enabled = config.summarizer_enabled
        @spell_check_enabled = config.spell_check_enabled
        @embedding_enabled = config.embedding_enabled
        @embedding_client = config.embedding_client
        load_active_persona
      end

      def initialize_console_system
        @console = ConsoleIO.new(db_history: @history, debug: @debug, application: self)
        @conversation_id = @history.create_conversation
        @event_bus = EventBus.new
        @formatter = Formatter.new(
          history: @history,
          session_start_time: @session_start_time,
          conversation_id: @conversation_id,
          orchestrator: @orchestrator,
          debug: @debug,
          console: @console,
          application: self,
          event_bus: @event_bus
        )
      end

      def initialize_status_tracking
        @status_mutex = Mutex.new
        @worker_manager = BackgroundWorkerManager.new(
          application: self,
          history: @history,
          summarizer: @summarizer,
          conversation_id: @conversation_id,
          status_mutex: @status_mutex,
          embedding_client: @embedding_client
        )
      end

      def initialize_commands
        @command_registry = Commands::CommandRegistry.new
        register_commands
      end

      def start_background_workers
        # Skip auto-start in CI environments to avoid background churn during tests
        return if ci_environment?

        @worker_manager.start_summarization_worker if @summarizer_enabled
        @worker_manager.start_embedding_worker if @embedding_enabled && @embedding_client
      end

      def register_commands
        @command_registry.register("/help", Commands::HelpCommand)
        @command_registry.register("/tools", Commands::ToolsCommand)
        @command_registry.register("/info", Commands::InfoCommand)
        @command_registry.register("/models", Commands::ModelsCommand)
        @command_registry.register("/persona", Commands::PersonaCommand)
        @command_registry.register("/personas", Commands::PersonaCommand)
        @command_registry.register("/worker", Commands::WorkerCommand)
        @command_registry.register("/rag", Commands::RagCommand)
        @command_registry.register("/migrate-exchanges", Commands::MigrateExchangesCommand)
        @command_registry.register("/backup", Commands::BackupCommand)
        @command_registry.register("/admin", Commands::AdminCommand)
        @command_registry.register("/exit", Commands::ExitCommand)
        @command_registry.register("/clear", Commands::ClearCommand)
        @command_registry.register("/debug", Commands::DebugCommand)
        @command_registry.register("/verbosity", Commands::VerbosityCommand)
        @command_registry.register("/redaction", Commands::RedactionCommand)
        @command_registry.register("/spellcheck", Commands::SpellcheckCommand)
        @command_registry.register("/reset", Commands::ResetCommand)
        @command_registry.register("/model", Commands::ModelCommand)

        # Subsystem debug verbosity commands
        @command_registry.register("/llm", Commands::Subsystems::LlmCommand)
        @command_registry.register("/messages", Commands::Subsystems::MessagesCommand)
        @command_registry.register("/search", Commands::Subsystems::SearchCommand)
        @command_registry.register("/stats", Commands::Subsystems::StatsCommand)
        @command_registry.register("/tools-debug", Commands::Subsystems::ToolsDebugCommand)
        @command_registry.register("/spellcheck-debug", Commands::Subsystems::SpellcheckDebugCommand)
      end

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

      def print_help
        @console.puts("")
        help_text = HelpTextBuilder.build
        output_lines(*help_text.lines.map(&:chomp), type: :debug)
      end

      public

      def handle_command(input)
        # Check if command is registered in the command registry
        command_name = input.split.first&.downcase
        return @command_registry.execute(command_name, input, self) if @command_registry.registered?(command_name)

        # Unknown command
        @console.puts("")
        output_line("Unknown command: #{input}", type: :debug)
        :continue
      end

      def run_fix
        DatabaseFixRunner.run(self)
      end

      def run_migrate_exchanges
        ExchangeMigrationRunner.run(self)
      end

      def print_info
        info_text = SessionInfo.build(self)
        output_lines(*info_text.lines.map(&:chomp), type: :command)
      end

      def print_models
        model_text = ModelDisplayFormatter.build
        output_lines(*model_text.lines.map(&:chomp), type: :command)
      end

      def print_tools
        tools_text = ToolsDisplayFormatter.build
        output_lines(*tools_text.lines.map(&:chomp), type: :command)
      end

      def start_summarization_worker
        @worker_manager.start_summarization_worker if @summarizer_enabled
      end

      def reload_active_persona
        load_active_persona
      end

      private

      def setup_signal_handlers
        # Don't trap INT - let it raise Interrupt exception so we can handle it gracefully
      end

      def print_welcome
        print "\033[2J\033[H"
        output_lines(
          "Nu Agent REPL",
          "Database: #{File.expand_path(@history.db_path)}",
          "Type your prompts below. Press Ctrl-C or /exit to quit.",
          "(Ctrl-C during processing aborts operation)",
          "Press Enter to submit input (Shift+Enter for newline)",
          "Type /help for available commands",
          "=" * 60
        )
      end

      def print_goodbye
        output_line("Goodbye!", type: :debug)
      end

      def load_active_persona
        persona_manager = PersonaManager.new(@history.connection)
        active_persona = persona_manager.get_active
        @active_persona_system_prompt = active_persona&.dig("system_prompt")
      rescue StandardError => e
        # If persona loading fails, fall back to nil (uses client default)
        output_line("Warning: Could not load persona: #{e.message}", type: :debug) if @debug
        @active_persona_system_prompt = nil
      end
    end
  end
end
