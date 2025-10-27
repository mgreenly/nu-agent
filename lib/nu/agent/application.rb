# frozen_string_literal: true

module Nu
  module Agent
    class Application
      attr_accessor :orchestrator, :spellchecker, :summarizer, :active_threads, :debug, :verbosity, :redact,
                    :summarizer_enabled, :spell_check_enabled, :conversation_id, :session_start_time
      attr_reader :history, :formatter, :summarizer_status, :man_indexer_status, :status_mutex, :console, :tui,
                  :operation_mutex

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
        @input_processor = InputProcessor.new(application: self, user_actor: @user_actor)
        # Load configuration (models and settings)
        config = ConfigurationLoader.load(history: @history, options: @options)
        @orchestrator = config.orchestrator
        @spellchecker = config.spellchecker
        @summarizer = config.summarizer
        @debug = config.debug
        @verbosity = config.verbosity
        @redact = config.redact
        @summarizer_enabled = config.summarizer_enabled
        @spell_check_enabled = config.spell_check_enabled

        # Initialize ConsoleIO (new unified console system)
        @console = ConsoleIO.new(db_history: @history, debug: @debug)
        @conversation_id = @history.create_conversation
        @formatter = Formatter.new(
          history: @history,
          session_start_time: @session_start_time,
          conversation_id: @conversation_id,
          orchestrator: @orchestrator,
          debug: @debug,
          console: @console,
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

        # Initialize command registry
        @command_registry = Commands::CommandRegistry.new
        register_commands

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
        @input_processor.process(input)
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

      # Clear the screen
      def clear_screen
        if @tui&.active
          @tui.clear_output
        else
          system("clear")
        end
      end

      private

      def register_commands
        @command_registry.register("/help", Commands::HelpCommand)
        @command_registry.register("/tools", Commands::ToolsCommand)
        @command_registry.register("/info", Commands::InfoCommand)
        @command_registry.register("/models", Commands::ModelsCommand)
        @command_registry.register("/fix", Commands::FixCommand)
        @command_registry.register("/migrate-exchanges", Commands::MigrateExchangesCommand)
        @command_registry.register("/exit", Commands::ExitCommand)
        @command_registry.register("/clear", Commands::ClearCommand)
        @command_registry.register("/debug", Commands::DebugCommand)
        @command_registry.register("/verbosity", Commands::VerbosityCommand)
        @command_registry.register("/redaction", Commands::RedactionCommand)
        @command_registry.register("/summarizer", Commands::SummarizerCommand)
        @command_registry.register("/spellcheck", Commands::SpellcheckCommand)
        @command_registry.register("/reset", Commands::ResetCommand)
        @command_registry.register("/model", Commands::ModelCommand)
        @command_registry.register("/index-man", Commands::IndexManCommand)
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
        output_lines(*info_text.lines.map(&:chomp), type: :debug)
      end

      def print_models
        model_text = ModelDisplayFormatter.build
        output_lines(*model_text.lines.map(&:chomp), type: :debug)
      end

      def print_tools
        tools_text = ToolsDisplayFormatter.build
        output_lines(*tools_text.lines.map(&:chomp), type: :debug)
      end

      def start_summarization_worker
        # Don't start if summarizer is disabled
        return unless @summarizer_enabled

        # Capture values for thread
        @operation_mutex.synchronize do
          # Create summarizer worker and start thread
          summarizer_worker = ConversationSummarizer.new(
            history: history,
            summarizer: @summarizer,
            application: self,
            status_info: { status: @summarizer_status, mutex: @status_mutex },
            current_conversation_id: conversation_id
          )

          thread = summarizer_worker.start_worker
          active_threads << thread
        end
      end

      def start_man_indexer_worker
        # Capture values for thread
        @operation_mutex.synchronize do
          # Create embeddings client
          begin
            embeddings_client = Clients::OpenAIEmbeddings.new
          rescue StandardError => e
            output_line("[Man Indexer] ERROR: Failed to create OpenAI Embeddings client", type: :error)
            output_line("  #{e.message}", type: :error)
            output_line("Man page indexing requires OpenAI embeddings API access.", type: :error)
            output_line("Please ensure your OpenAI API key has access to text-embedding-3-small.", type: :error)
            @status_mutex.synchronize { @man_indexer_status["running"] = false }
            return
          end

          # Create indexer and start worker
          indexer = ManPageIndexer.new(
            history: history,
            embeddings_client: embeddings_client,
            application: self,
            status: @man_indexer_status,
            status_mutex: @status_mutex
          )

          thread = indexer.start_worker
          active_threads << thread
        end
      end

      private

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
    end
  end
end
