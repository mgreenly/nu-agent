# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Application do
  let(:options) do
    instance_double(
      Nu::Agent::Options,
      debug: false,
      reset_model: nil
    )
  end

  let(:mock_connection) do
    instance_double("DuckDB::Connection")
  end

  let(:mock_persona_manager) do
    instance_double(
      Nu::Agent::PersonaManager,
      get_active: { "system_prompt" => "Test persona prompt" }
    )
  end

  let(:mock_history) do
    instance_double(
      Nu::Agent::History,
      get_config: nil,
      set_config: nil,
      create_conversation: 1,
      close: nil,
      db_path: "/tmp/test.db",
      connection: mock_connection
    )
  end

  let(:mock_console) do
    instance_double(
      Nu::Agent::ConsoleIO,
      readline: nil,
      puts: nil,
      show_spinner: nil,
      hide_spinner: nil,
      close: nil
    )
  end

  let(:mock_worker_manager) do
    instance_double(
      Nu::Agent::BackgroundWorkerManager,
      active_threads: [],
      summarizer_status: "idle",
      start_summarization_worker: nil
    )
  end

  before do
    # Mock History.new
    allow(Nu::Agent::History).to receive(:new).and_return(mock_history)

    # Mock ConsoleIO.new
    allow(Nu::Agent::ConsoleIO).to receive(:new).and_return(mock_console)

    # Mock ClientFactory
    mock_client = instance_double("Client", model: "test-model", max_context: 100_000)
    allow(Nu::Agent::ClientFactory).to receive(:create).and_return(mock_client)

    # Mock BackgroundWorkerManager.new
    allow(Nu::Agent::BackgroundWorkerManager).to receive(:new).and_return(mock_worker_manager)

    # Mock PersonaManager.new
    allow(Nu::Agent::PersonaManager).to receive(:new).and_return(mock_persona_manager)

    # Setup default config responses
    allow(mock_history).to receive(:get_config).with("model_orchestrator").and_return("test-model")
    allow(mock_history).to receive(:get_config).with("model_summarizer").and_return("test-model")
    allow(mock_history).to receive(:get_config).with("debug", default: "false").and_return("false")
    allow(mock_history).to receive(:get_config).with("verbosity", default: "0").and_return("0")
    allow(mock_history).to receive(:get_config).with("redaction", default: "true").and_return("true")
    allow(mock_history).to receive(:get_config).with("summarizer_enabled", default: "true").and_return("false")

    # Mock stdout.sync
    allow($stdout).to receive(:sync=)

    # Mock ENV
    allow(ENV).to receive(:[]).with("USER").and_return("testuser")
  end

  describe "#initialize" do
    it "initializes all required components" do
      app = described_class.new(options: options)

      expect(app.debug).to be false
      expect(app.history).to eq(mock_history)
      expect(app.console).to eq(mock_console)
      expect(app.formatter).to be_a(Nu::Agent::Formatter)
    end

    it "sets session_start_time" do
      time_before = Time.now
      app = described_class.new(options: options)
      time_after = Time.now

      expect(app.session_start_time).to be_between(time_before, time_after)
    end

    it "creates a conversation" do
      expect(mock_history).to receive(:create_conversation).and_return(42)
      app = described_class.new(options: options)
      expect(app.conversation_id).to eq(42)
    end
  end

  describe "#active_threads" do
    it "returns active threads from worker_manager" do
      app = described_class.new(options: options)
      mock_thread = Thread.new { sleep 0.01 }
      allow(mock_worker_manager).to receive(:active_threads).and_return([mock_thread])

      expect(app.active_threads).to eq([mock_thread])

      mock_thread.kill
      mock_thread.join
    end

    it "returns empty array when worker_manager is nil" do
      app = described_class.new(options: options)
      app.instance_variable_set(:@worker_manager, nil)

      expect(app.active_threads).to eq([])
    end
  end

  describe "#summarizer_status" do
    it "returns status from worker_manager" do
      app = described_class.new(options: options)
      allow(mock_worker_manager).to receive(:summarizer_status).and_return("running")

      expect(app.summarizer_status).to eq("running")
    end

    it "returns nil when worker_manager is nil" do
      app = described_class.new(options: options)
      app.instance_variable_set(:@worker_manager, nil)

      expect(app.summarizer_status).to be_nil
    end
  end

  describe "#process_input" do
    it "delegates to input_processor" do
      app = described_class.new(options: options)
      input_processor = app.instance_variable_get(:@input_processor)
      allow(input_processor).to receive(:process).with("test input").and_return(:continue)

      result = app.process_input("test input")

      expect(result).to eq(:continue)
    end
  end

  describe "#clear_screen" do
    it "calls system to clear screen" do
      app = described_class.new(options: options)
      expect(app).to receive(:system).with("clear")

      app.clear_screen
    end
  end

  describe "#run_fix" do
    it "delegates to DatabaseFixRunner" do
      app = described_class.new(options: options)
      expect(Nu::Agent::DatabaseFixRunner).to receive(:run).with(app)

      app.run_fix
    end
  end

  describe "#run_migrate_exchanges" do
    it "delegates to ExchangeMigrationRunner" do
      app = described_class.new(options: options)
      expect(Nu::Agent::ExchangeMigrationRunner).to receive(:run).with(app)

      app.run_migrate_exchanges
    end
  end

  describe "#print_info" do
    it "builds and outputs session info with command formatting" do
      app = described_class.new(options: options)
      info_text = "Session Info\nLine 1\nLine 2"
      allow(Nu::Agent::SessionInfo).to receive(:build).with(app).and_return(info_text)

      expect(mock_console).to receive(:puts).with("\e[90mSession Info\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90mLine 1\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90mLine 2\e[0m")

      app.print_info
    end
  end

  describe "#print_models" do
    it "builds and outputs model display with command formatting" do
      app = described_class.new(options: options)
      model_text = "Available Models\nModel 1\nModel 2"
      allow(Nu::Agent::ModelDisplayFormatter).to receive(:build).and_return(model_text)

      expect(mock_console).to receive(:puts).with("\e[90mAvailable Models\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90mModel 1\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90mModel 2\e[0m")

      app.print_models
    end
  end

  describe "#print_tools" do
    it "builds and outputs tools display with command formatting" do
      app = described_class.new(options: options)
      tools_text = "Available Tools\nTool 1\nTool 2"
      allow(Nu::Agent::ToolsDisplayFormatter).to receive(:build).and_return(tools_text)

      expect(mock_console).to receive(:puts).with("\e[90mAvailable Tools\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90mTool 1\e[0m")
      expect(mock_console).to receive(:puts).with("\e[90mTool 2\e[0m")

      app.print_tools
    end
  end

  describe "#start_summarization_worker" do
    it "starts worker when summarizer is enabled" do
      allow(mock_history).to receive(:get_config).with("summarizer_enabled", default: "true").and_return("true")
      app = described_class.new(options: options)
      app.instance_variable_set(:@summarizer_enabled, true)

      expect(mock_worker_manager).to receive(:start_summarization_worker)

      app.start_summarization_worker
    end

    it "does not start worker when summarizer is disabled" do
      app = described_class.new(options: options)
      app.instance_variable_set(:@summarizer_enabled, false)

      expect(mock_worker_manager).not_to receive(:start_summarization_worker)

      app.start_summarization_worker
    end
  end

  describe "#handle_command" do
    let(:app) { described_class.new(options: options) }

    it "delegates to command registry for registered commands" do
      command_registry = app.instance_variable_get(:@command_registry)
      expect(command_registry).to receive(:registered?).with("/exit").and_return(true)
      expect(command_registry).to receive(:execute).with("/exit", "/exit", app).and_return(:exit)

      result = app.handle_command("/exit")

      expect(result).to eq(:exit)
    end

    it "returns continue for unknown commands with error message" do
      expect(mock_console).to receive(:puts).with("")
      allow(options).to receive(:debug).and_return(true)
      allow(mock_history).to receive(:get_config).with("debug", default: "false").and_return("true")
      app_with_debug = described_class.new(options: options)
      expect(mock_console).to receive(:puts).with("\e[90mUnknown command: /unknown\e[0m")

      result = app_with_debug.handle_command("/unknown")

      expect(result).to eq(:continue)
    end
  end

  describe "command registration" do
    let(:app) { described_class.new(options: options) }
    let(:command_registry) { app.instance_variable_get(:@command_registry) }

    it "registers /worker command" do
      expect(command_registry.registered?("/worker")).to be true
    end

    it "registers /rag command" do
      expect(command_registry.registered?("/rag")).to be true
    end

    it "does not register deprecated /summarizer command" do
      expect(command_registry.registered?("/summarizer")).to be false
    end

    it "does not register deprecated /embeddings command" do
      expect(command_registry.registered?("/embeddings")).to be false
    end

    it "does not register deprecated /fix command" do
      expect(command_registry.registered?("/fix")).to be false
    end

    describe "#registered_commands" do
      it "returns all registered commands from the command registry" do
        # This test verifies that Application provides public access to registered commands
        expect { app.registered_commands }.not_to raise_error

        commands = app.registered_commands
        expect(commands).to be_a(Hash)
        expect(commands.keys).to include("/help", "/exit", "/clear", "/reset")
        expect(commands.keys).to include("/llm", "/messages", "/search", "/stats", "/tools-debug")
        expect(commands["/help"]).to eq(Nu::Agent::Commands::HelpCommand)
        expect(commands["/llm"]).to eq(Nu::Agent::Commands::Subsystems::LlmCommand)
      end
    end
  end

  describe "#run" do
    let(:app) { described_class.new(options: options) }

    it "runs the REPL and prints welcome/goodbye" do
      allow(app).to receive(:setup_signal_handlers)
      allow(app).to receive(:print_welcome)
      allow(app).to receive(:repl)
      allow(app).to receive(:print_goodbye)
      allow(mock_history).to receive(:close)

      app.run

      expect(app).to have_received(:print_welcome)
      expect(app).to have_received(:repl)
      expect(app).to have_received(:print_goodbye)
    end

    it "closes history even if exception occurs" do
      allow(app).to receive(:setup_signal_handlers)
      allow(app).to receive(:print_welcome)
      allow(app).to receive(:repl).and_raise(StandardError.new("test error"))
      allow(app).to receive(:print_goodbye)
      expect(mock_history).to receive(:close)

      expect { app.run }.to raise_error(StandardError, "test error")
    end

    it "waits for active threads to complete on shutdown" do
      allow(app).to receive(:setup_signal_handlers)
      allow(app).to receive(:print_welcome)
      allow(app).to receive(:repl)
      allow(app).to receive(:print_goodbye)

      mock_thread = instance_double(Thread)
      allow(mock_worker_manager).to receive(:active_threads).and_return([mock_thread])
      expect(mock_thread).to receive(:join)
      expect(mock_history).to receive(:close)

      app.run
    end

    it "waits for critical sections to complete before shutdown" do
      allow(app).to receive(:setup_signal_handlers)
      allow(app).to receive(:print_welcome)
      allow(app).to receive(:repl)
      allow(app).to receive(:print_goodbye)
      expect(mock_history).to receive(:close)

      # Simulate a critical section
      app.send(:enter_critical_section)

      # Start a thread that will exit the critical section after a short delay
      Thread.new do
        sleep 0.1
        app.send(:exit_critical_section)
      end

      start_time = Time.now
      app.run
      elapsed = Time.now - start_time

      # Should have waited for the critical section to complete
      expect(elapsed).to be >= 0.1
    end
  end

  describe "#repl" do
    let(:app) { described_class.new(options: options) }

    it "processes input until exit command" do
      allow(mock_console).to receive(:puts).with("")
      allow(mock_console).to receive(:readline).with("> ").and_return("test input", "exit")
      input_processor = app.instance_variable_get(:@input_processor)
      allow(input_processor).to receive(:process).with("test input").and_return(:continue)
      allow(input_processor).to receive(:process).with("exit").and_return(:exit)

      app.send(:repl)

      expect(mock_console).to have_received(:readline).twice
    end

    it "skips empty input" do
      allow(mock_console).to receive(:puts).with("")
      allow(mock_console).to receive(:readline).with("> ").and_return("", "  ", nil)

      app.send(:repl)
    end

    it "exits on Ctrl+D (nil input)" do
      allow(mock_console).to receive(:puts).with("")
      allow(mock_console).to receive(:readline).with("> ").and_return(nil)

      app.send(:repl)
    end

    it "exits on Interrupt during readline" do
      allow(mock_console).to receive(:puts).with("")
      allow(mock_console).to receive(:readline).with("> ").and_raise(Interrupt)

      app.send(:repl)
    end
  end

  describe "critical section management" do
    let(:app) { described_class.new(options: options) }

    it "tracks entering and exiting critical sections" do
      expect(app.send(:in_critical_section?)).to be false

      app.send(:enter_critical_section)
      expect(app.send(:in_critical_section?)).to be true

      app.send(:exit_critical_section)
      expect(app.send(:in_critical_section?)).to be false
    end

    it "handles multiple nested critical sections" do
      app.send(:enter_critical_section)
      app.send(:enter_critical_section)
      expect(app.send(:in_critical_section?)).to be true

      app.send(:exit_critical_section)
      expect(app.send(:in_critical_section?)).to be true

      app.send(:exit_critical_section)
      expect(app.send(:in_critical_section?)).to be false
    end
  end

  describe "#print_welcome" do
    let(:app) { described_class.new(options: options) }

    it "prints welcome message with database path" do
      expect(app).to receive(:print).with("\033[2J\033[H")
      expect(mock_console).to receive(:puts).with("Nu Agent REPL")
      expect(mock_console).to receive(:puts).with("Database: /tmp/test.db")
      expect(mock_console).to receive(:puts).with("Type your prompts below. Press Ctrl-C or /exit to quit.")
      expect(mock_console).to receive(:puts).with("(Ctrl-C during processing aborts operation)")
      expect(mock_console).to receive(:puts).with("Type /help for available commands")
      expect(mock_console).to receive(:puts).with("=" * 60)

      app.send(:print_welcome)
    end
  end

  describe "#print_goodbye" do
    it "prints goodbye message with debug formatting when debug is enabled" do
      allow(options).to receive(:debug).and_return(true)
      allow(mock_history).to receive(:get_config).with("debug", default: "false").and_return("true")
      app = described_class.new(options: options)

      expect(mock_console).to receive(:puts).with("\e[90mGoodbye!\e[0m")

      app.send(:print_goodbye)
    end

    it "does not print goodbye when debug is disabled" do
      app = described_class.new(options: options)

      expect(mock_console).not_to receive(:puts)

      app.send(:print_goodbye)
    end
  end

  describe "#setup_signal_handlers" do
    let(:app) { described_class.new(options: options) }

    it "does not trap signals" do
      # This method intentionally does nothing
      expect { app.send(:setup_signal_handlers) }.not_to raise_error
    end
  end

  describe "#reopen_database" do
    let(:new_history) do
      instance_double(
        Nu::Agent::History,
        get_config: nil,
        set_config: nil,
        create_conversation: 1,
        close: nil,
        db_path: "/tmp/test_new.db"
      )
    end

    it "creates a new History object" do
      app = described_class.new(options: options)
      old_history = app.history

      # Mock History.new to return a new instance
      allow(Nu::Agent::History).to receive(:new).and_return(new_history)

      app.reopen_database

      expect(app.history).to eq(new_history)
      expect(app.history).not_to eq(old_history)
    end

    it "updates console's db_history reference" do
      app = described_class.new(options: options)
      allow(Nu::Agent::History).to receive(:new).and_return(new_history)

      app.reopen_database

      console_history = app.console.instance_variable_get(:@db_history)
      expect(console_history).to eq(new_history)
    end

    it "updates formatter's history reference" do
      app = described_class.new(options: options)
      allow(Nu::Agent::History).to receive(:new).and_return(new_history)

      app.reopen_database

      formatter_history = app.formatter.instance_variable_get(:@history)
      expect(formatter_history).to eq(new_history)
    end

    it "updates worker_manager's history reference" do
      app = described_class.new(options: options)
      allow(Nu::Agent::History).to receive(:new).and_return(new_history)

      app.reopen_database

      worker_manager_history = app.worker_manager.instance_variable_get(:@history)
      expect(worker_manager_history).to eq(new_history)
    end

    it "updates worker instances' history references" do
      app = described_class.new(options: options)
      allow(Nu::Agent::History).to receive(:new).and_return(new_history)

      # Create a mock worker with history reference
      mock_worker = double("Worker")
      allow(mock_worker).to receive(:instance_variable_defined?).with(:@history).and_return(true)
      allow(mock_worker).to receive(:instance_variable_set).with(:@history, new_history)

      worker_instances = { "test-worker" => mock_worker }
      allow(app.worker_manager).to receive(:instance_variable_get).with(:@worker_instances).and_return(worker_instances)

      app.reopen_database

      expect(mock_worker).to have_received(:instance_variable_set).with(:@history, new_history)
    end
  end

  describe "#start_background_workers" do
    before do
      allow(mock_history).to receive(:get_config).with("summarizer_enabled", default: "true").and_return("true")
      allow(mock_worker_manager).to receive(:start_summarization_worker)
      allow(mock_worker_manager).to receive(:start_embedding_worker)
    end

    context "in development environment" do
      before do
        allow(ENV).to receive(:fetch).with("CI", "false").and_return("false")
      end

      it "does not start workers during initialization" do
        described_class.new(options: options)
        expect(mock_worker_manager).not_to have_received(:start_summarization_worker)
      end

      it "starts workers during run() after print_welcome" do
        app = described_class.new(options: options)

        # Set up expectations in order
        expect(app).to receive(:setup_signal_handlers).ordered
        expect(app).to receive(:print_welcome).ordered
        expect(mock_worker_manager).to receive(:start_summarization_worker).ordered
        expect(app).to receive(:repl).ordered
        expect(app).to receive(:print_goodbye).ordered
        allow(mock_history).to receive(:close)

        app.run
      end
    end

    context "in CI environment" do
      before do
        allow(ENV).to receive(:fetch).with("CI", "false").and_return("true")
      end

      it "does not auto-start workers even when enabled" do
        app = described_class.new(options: options)

        allow(app).to receive(:setup_signal_handlers)
        allow(app).to receive(:print_welcome)
        allow(app).to receive(:repl)
        allow(app).to receive(:print_goodbye)
        allow(mock_history).to receive(:close)

        app.run

        expect(mock_worker_manager).not_to have_received(:start_summarization_worker)
      end
    end
  end

  describe "#exchange_summarizer_status" do
    it "delegates to worker_manager" do
      allow(mock_worker_manager).to receive(:exchange_summarizer_status).and_return("test_status")
      app = described_class.new(options: options)

      result = app.exchange_summarizer_status
      expect(result).to eq("test_status")
    end
  end

  describe "#embedding_status" do
    it "delegates to worker_manager" do
      allow(mock_worker_manager).to receive(:embedding_status).and_return("embedding_status_value")
      app = described_class.new(options: options)

      result = app.embedding_status
      expect(result).to eq("embedding_status_value")
    end
  end

  describe "#print_help" do
    it "prints help text using HelpTextBuilder" do
      app = described_class.new(options: options)
      help_text = "Help line 1\nHelp line 2\n"

      allow(Nu::Agent::HelpTextBuilder).to receive(:build).and_return(help_text)
      allow(app).to receive(:output_lines)

      app.send(:print_help)

      expect(mock_console).to have_received(:puts).with("")
      expect(app).to have_received(:output_lines).with("Help line 1", "Help line 2", type: :debug)
    end
  end

  describe "#reload_active_persona" do
    it "reloads the active persona" do
      app = described_class.new(options: options)

      # Expect PersonaManager to be called again
      new_persona_manager = instance_double(Nu::Agent::PersonaManager)
      allow(Nu::Agent::PersonaManager).to receive(:new).and_return(new_persona_manager)
      allow(new_persona_manager).to receive(:get_active).and_return({ "system_prompt" => "New prompt" })

      app.reload_active_persona

      expect(Nu::Agent::PersonaManager).to have_received(:new).at_least(:once)
    end
  end

  describe "persona loading error handling" do
    it "handles errors when loading persona gracefully with debug enabled" do
      error_persona_manager = instance_double(Nu::Agent::PersonaManager)
      allow(Nu::Agent::PersonaManager).to receive(:new).and_return(error_persona_manager)
      allow(error_persona_manager).to receive(:get_active).and_raise(StandardError.new("Persona error"))

      # Enable debug mode for the application
      debug_options = instance_double(Nu::Agent::Options, debug: true, reset_model: nil)
      allow(mock_history).to receive(:get_config).with("debug", default: "false").and_return("true")

      # We need to capture output_line calls during initialization
      output_calls = []
      allow_any_instance_of(described_class).to receive(:output_line) do |_, *args|
        output_calls << args
      end

      app = described_class.new(options: debug_options)

      # Should not raise, persona should be nil
      expect(app.instance_variable_get(:@active_persona_system_prompt)).to be_nil
      expect(output_calls.any? { |call| call[0]&.include?("Warning: Could not load persona") }).to be true
    end
  end
end
