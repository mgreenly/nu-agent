# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/model_command"

RSpec.describe Nu::Agent::Commands::ModelCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:formatter) { instance_double("Nu::Agent::Formatter") }
  let(:orchestrator) { instance_double("Nu::Agent::Clients::Base", model: "gpt-4", name: "OpenAI") }
  let(:spellchecker) { instance_double("Nu::Agent::Clients::Base", model: "gpt-4-mini") }
  let(:summarizer) { instance_double("Nu::Agent::Clients::Base", model: "claude-3-5-haiku") }
  let(:operation_mutex) { Mutex.new }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive(:console).and_return(console)
    allow(application).to receive(:history).and_return(history)
    allow(application).to receive(:formatter).and_return(formatter)
    allow(application).to receive(:operation_mutex).and_return(operation_mutex)
    allow(application).to receive(:active_threads).and_return([])
    allow(application).to receive(:output_line)
    allow(console).to receive(:puts)

    # Allow orchestrator, spellchecker, summarizer to be read and written
    @current_orchestrator = orchestrator
    @current_spellchecker = spellchecker
    @current_summarizer = summarizer
    allow(application).to receive(:orchestrator) { @current_orchestrator }
    allow(application).to receive(:orchestrator=) { |val| @current_orchestrator = val }
    allow(application).to receive(:spellchecker) { @current_spellchecker }
    allow(application).to receive(:spellchecker=) { |val| @current_spellchecker = val }
    allow(application).to receive(:summarizer) { @current_summarizer }
    allow(application).to receive(:summarizer=) { |val| @current_summarizer = val }
  end

  describe "#execute" do
    context "when called without arguments" do
      it "shows current models" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Current Models:", type: :debug)
        expect(application).to receive(:output_line).with("  Orchestrator:  gpt-4", type: :debug)
        expect(application).to receive(:output_line).with("  Spellchecker:  gpt-4-mini", type: :debug)
        expect(application).to receive(:output_line).with("  Summarizer:    claude-3-5-haiku", type: :debug)

        result = command.execute("/model")
        expect(result).to eq(:continue)
      end
    end

    context "when called with insufficient arguments" do
      it "shows usage message" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Usage:", type: :debug)
        expect(application).to receive(:output_line).with("  /model                        Show current models",
                                                          type: :debug)
        expect(application).to receive(:output_line).with("  /model orchestrator <name>    Set orchestrator model",
                                                          type: :debug)
        expect(application).to receive(:output_line).with("  /model spellchecker <name>    Set spellchecker model",
                                                          type: :debug)
        expect(application).to receive(:output_line).with("  /model summarizer <name>      Set summarizer model",
                                                          type: :debug)
        expect(application).to receive(:output_line).with("Example: /model orchestrator gpt-5", type: :debug)
        expect(application).to receive(:output_line).with("Run /models to see available models", type: :debug)

        result = command.execute("/model orchestrator")
        expect(result).to eq(:continue)
      end
    end

    context "when switching orchestrator model" do
      let(:new_client) { instance_double("Nu::Agent::Clients::Base", model: "gpt-5", name: "OpenAI") }

      before do
        stub_const("Nu::Agent::ClientFactory", Class.new)
        allow(Nu::Agent::ClientFactory).to receive(:create).with("gpt-5").and_return(new_client)
        allow(formatter).to receive(:orchestrator=)
        allow(history).to receive(:set_config)
      end

      it "switches orchestrator model under mutex" do
        expect(Nu::Agent::ClientFactory).to receive(:create).with("gpt-5")
        expect(application).to receive(:orchestrator=).with(new_client)
        expect(formatter).to receive(:orchestrator=).with(new_client)
        expect(history).to receive(:set_config).with("model_orchestrator", "gpt-5")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Switched orchestrator to: OpenAI (gpt-5)", type: :debug)

        result = command.execute("/model orchestrator gpt-5")
        expect(result).to eq(:continue)
      end

      context "when there are active threads" do
        let(:active_thread) { Thread.new { sleep 0.1 } } # Sleep longer than join timeout (0.05s)

        before do
          allow(application).to receive(:active_threads).and_return([active_thread])
        end

        it "waits for active threads to complete" do
          expect(application).to receive(:output_line).with("Waiting for current operation to complete...",
                                                            type: :debug)
          command.execute("/model orchestrator gpt-5")
          expect(active_thread.status).to be_falsey
        end
      end

      context "when ClientFactory raises an error" do
        before do
          error = Nu::Agent::Error.new("Model not found")
          allow(Nu::Agent::ClientFactory).to receive(:create).and_raise(error)
        end

        it "outputs error message and continues" do
          expect(application).to receive(:output_line).with("Error: Model not found", type: :error)
          result = command.execute("/model orchestrator invalid")
          expect(result).to eq(:continue)
        end
      end
    end

    context "when switching spellchecker model" do
      let(:new_client) { instance_double("Nu::Agent::Clients::Base") }

      before do
        stub_const("Nu::Agent::ClientFactory", Class.new)
        allow(Nu::Agent::ClientFactory).to receive(:create).with("gpt-5").and_return(new_client)
        allow(history).to receive(:set_config)
      end

      it "switches spellchecker model" do
        expect(Nu::Agent::ClientFactory).to receive(:create).with("gpt-5")
        expect(application).to receive(:spellchecker=).with(new_client)
        expect(history).to receive(:set_config).with("model_spellchecker", "gpt-5")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Switched spellchecker to: gpt-5", type: :debug)

        result = command.execute("/model spellchecker gpt-5")
        expect(result).to eq(:continue)
      end

      context "when ClientFactory raises an error" do
        before do
          error = Nu::Agent::Error.new("Model not found")
          allow(Nu::Agent::ClientFactory).to receive(:create).and_raise(error)
        end

        it "outputs error message and continues" do
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with("Error: Model not found", type: :error)
          result = command.execute("/model spellchecker invalid")
          expect(result).to eq(:continue)
        end
      end
    end

    context "when switching summarizer model" do
      let(:new_client) { instance_double("Nu::Agent::Clients::Base") }

      before do
        stub_const("Nu::Agent::ClientFactory", Class.new)
        allow(Nu::Agent::ClientFactory).to receive(:create).with("claude-3-5-sonnet").and_return(new_client)
        allow(history).to receive(:set_config)
      end

      it "switches summarizer model with note about next session" do
        expect(Nu::Agent::ClientFactory).to receive(:create).with("claude-3-5-sonnet")
        expect(application).to receive(:summarizer=).with(new_client)
        expect(history).to receive(:set_config).with("model_summarizer", "claude-3-5-sonnet")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Switched summarizer to: claude-3-5-sonnet", type: :debug)
        expect(application).to receive(:output_line)
          .with("Note: Change takes effect at the start of the next session (/reset)", type: :debug)

        result = command.execute("/model summarizer claude-3-5-sonnet")
        expect(result).to eq(:continue)
      end

      context "when ClientFactory raises an error" do
        before do
          error = Nu::Agent::Error.new("Model not found")
          allow(Nu::Agent::ClientFactory).to receive(:create).and_raise(error)
        end

        it "outputs error message and continues" do
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with("Error: Model not found", type: :error)
          result = command.execute("/model summarizer invalid")
          expect(result).to eq(:continue)
        end
      end
    end

    context "when using unknown subcommand" do
      it "shows error message" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Unknown subcommand: unknown", type: :debug)
        expect(application).to receive(:output_line)
          .with("Valid subcommands: orchestrator, spellchecker, summarizer", type: :debug)

        result = command.execute("/model unknown some-model")
        expect(result).to eq(:continue)
      end
    end
  end
end
