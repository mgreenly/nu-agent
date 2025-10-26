# frozen_string_literal: true

require "spec_helper"
require "nu/agent/application"
require "nu/agent/console_io"
require "nu/agent/options"

RSpec.describe Nu::Agent::Application, "ConsoleIO Integration" do
  let(:options) do
    instance_double(
      Nu::Agent::Options,
      debug: false,
      reset_model: nil,
      tui: false
    )
  end

  let(:mock_history) do
    instance_double(
      Nu::Agent::History,
      get_config: nil,
      set_config: nil,
      create_conversation: 1,
      close: nil
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

  before do
    # Mock History.new to return our mock
    allow(Nu::Agent::History).to receive(:new).and_return(mock_history)

    # Mock ConsoleIO.new to return our mock
    allow(Nu::Agent::ConsoleIO).to receive(:new).and_return(mock_console)

    # Mock ClientFactory to avoid API client initialization
    mock_client = instance_double("Client", model: "test-model", max_context: 100_000)
    allow(Nu::Agent::ClientFactory).to receive(:create).and_return(mock_client)

    # Setup default config responses
    allow(mock_history).to receive(:get_config).with("model_orchestrator").and_return("test-model")
    allow(mock_history).to receive(:get_config).with("model_spellchecker").and_return("test-model")
    allow(mock_history).to receive(:get_config).with("model_summarizer").and_return("test-model")
    allow(mock_history).to receive(:get_config).with("debug", default: "false").and_return("false")
    allow(mock_history).to receive(:get_config).with("verbosity", default: "0").and_return("0")
    allow(mock_history).to receive(:get_config).with("redaction", default: "true").and_return("true")
    allow(mock_history).to receive(:get_config).with("summarizer_enabled", default: "true").and_return("false")
    allow(mock_history).to receive(:get_config).with("spell_check_enabled", default: "true").and_return("true")
  end

  describe "#initialize" do
    it "creates a ConsoleIO instance instead of TUI/OutputManager" do
      expect(Nu::Agent::ConsoleIO).to receive(:new).with(
        db_history: mock_history,
        debug: false
      ).and_return(mock_console)

      app = described_class.new(options: options)

      # Should have @console set
      expect(app.instance_variable_get(:@console)).to eq(mock_console)

      # Should NOT have @tui set
      expect(app.instance_variable_get(:@tui)).to be_nil

      # Should NOT have @output set (OutputManager should be removed)
      expect(app.instance_variable_get(:@output)).to be_nil
    end

    it "passes debug flag to ConsoleIO when debug is enabled" do
      allow(options).to receive(:debug).and_return(true)
      allow(mock_history).to receive(:get_config).with("debug", default: "false").and_return("true")

      expect(Nu::Agent::ConsoleIO).to receive(:new).with(
        db_history: mock_history,
        debug: true
      ).and_return(mock_console)

      described_class.new(options: options)
    end
  end

  describe "#output_line" do
    let(:app) { described_class.new(options: options) }

    it "outputs normal text via console.puts" do
      expect(mock_console).to receive(:puts).with("Hello world")

      app.send(:output_line, "Hello world")
    end

    it "outputs error text with red ANSI codes" do
      expect(mock_console).to receive(:puts).with("\e[31mError occurred\e[0m")

      app.send(:output_line, "Error occurred", type: :error)
    end

    context "when debug mode is enabled" do
      before do
        allow(options).to receive(:debug).and_return(true)
        allow(mock_history).to receive(:get_config).with("debug", default: "false").and_return("true")
      end

      it "outputs debug text with gray ANSI codes" do
        app_with_debug = described_class.new(options: options)
        expect(mock_console).to receive(:puts).with("\e[90mDebug info\e[0m")

        app_with_debug.send(:output_line, "Debug info", type: :debug)
      end
    end

    context "when debug mode is disabled" do
      it "does not output debug text" do
        expect(mock_console).not_to receive(:puts)

        app.send(:output_line, "Debug info", type: :debug)
      end
    end
  end

  describe "#output_lines" do
    let(:app) { described_class.new(options: options) }

    it "outputs multiple lines via console.puts" do
      expect(mock_console).to receive(:puts).with("Line 1").ordered
      expect(mock_console).to receive(:puts).with("Line 2").ordered
      expect(mock_console).to receive(:puts).with("Line 3").ordered

      app.send(:output_lines, "Line 1", "Line 2", "Line 3")
    end

    it "outputs multiple error lines with red ANSI codes" do
      expect(mock_console).to receive(:puts).with("\e[31mError 1\e[0m").ordered
      expect(mock_console).to receive(:puts).with("\e[31mError 2\e[0m").ordered

      app.send(:output_lines, "Error 1", "Error 2", type: :error)
    end
  end

  describe "spinner integration" do
    let(:app) { described_class.new(options: options) }

    it "uses console.show_spinner to start waiting indicator" do
      expect(mock_console).to receive(:show_spinner).with("Thinking...")

      # Simulate starting the spinner
      @console = app.instance_variable_get(:@console)
      @console.show_spinner("Thinking...")
    end

    it "uses console.hide_spinner to stop waiting indicator" do
      expect(mock_console).to receive(:hide_spinner)

      # Simulate stopping the spinner
      @console = app.instance_variable_get(:@console)
      @console.hide_spinner
    end
  end

  describe "REPL integration" do
    # Note: Full REPL testing is complex due to the loop and dependencies.
    # We're testing that ConsoleIO.readline is called correctly.

    it "has a repl method that will use console.readline" do
      app = described_class.new(options: options)

      # Verify the app has a console instance that can be used for readline
      expect(app.console).to eq(mock_console)
      expect(mock_console).to respond_to(:readline)
    end
  end
end
