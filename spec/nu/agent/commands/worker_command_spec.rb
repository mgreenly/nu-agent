# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/worker_command"

RSpec.describe Nu::Agent::Commands::WorkerCommand do
  let(:application) { double("Nu::Agent::Application") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:worker_manager) { instance_double("Nu::Agent::BackgroundWorkerManager") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(console: console, worker_manager: worker_manager, history: history)
    allow(application).to receive(:output_line)
    allow(application).to receive(:output_lines)
    allow(console).to receive(:puts)
    allow(history).to receive(:get_int).and_return(0)
  end

  describe "#execute" do
    context "when no argument provided" do
      it "displays general help" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_lines) do |*lines, type:|
          expect(type).to eq(:command)
          help_text = lines.join("\n")
          expect(help_text).to include("Available workers:")
          expect(help_text).to include("conversation-summarizer")
          expect(help_text).to include("exchange-summarizer")
          expect(help_text).to include("embeddings")
          expect(help_text).to include("/worker status")
        end
        command.execute("/worker")
      end

      it "returns :continue" do
        expect(command.execute("/worker")).to eq(:continue)
      end
    end

    context "when 'help' argument provided" do
      it "displays general help" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_lines) do |*lines, type:|
          expect(type).to eq(:command)
          help_text = lines.join("\n")
          expect(help_text).to include("Available workers:")
        end
        command.execute("/worker help")
      end

      it "returns :continue" do
        expect(command.execute("/worker help")).to eq(:continue)
      end
    end

    context "when 'status' argument provided" do
      let(:summarizer_status) do
        {
          "running" => false,
          "total" => 15,
          "completed" => 15,
          "failed" => 0,
          "spend" => 0.03
        }
      end

      let(:exchange_status) do
        {
          "running" => true,
          "total" => 42,
          "completed" => 42,
          "failed" => 0,
          "spend" => 0.01
        }
      end

      let(:embedding_status) do
        {
          "running" => false,
          "total" => 57,
          "completed" => 57,
          "failed" => 0,
          "spend" => 0.02
        }
      end

      before do
        allow(worker_manager).to receive_messages(
          summarizer_status: summarizer_status,
          exchange_summarizer_status: exchange_status,
          embedding_status: embedding_status
        )
      end

      it "displays status for all workers" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_lines) do |*lines, type:|
          expect(type).to eq(:command)
          status_text = lines.join("\n")
          expect(status_text).to include("Workers:")
          expect(status_text).to include("conversation-summarizer")
          expect(status_text).to include("exchange-summarizer")
          expect(status_text).to include("embeddings")
          expect(status_text).to include("15 completed")
          expect(status_text).to include("42 completed")
          expect(status_text).to include("57 completed")
        end
        command.execute("/worker status")
      end

      it "returns :continue" do
        expect(command.execute("/worker status")).to eq(:continue)
      end
    end

    context "when valid worker name provided" do
      let(:worker_handler) { instance_double("Nu::Agent::Commands::Workers::ConversationSummarizerCommand") }

      before do
        allow(command).to receive(:create_worker_handler).with("conversation-summarizer").and_return(worker_handler)
      end

      context "with no subcommand" do
        it "delegates to worker handler help" do
          expect(worker_handler).to receive(:execute_subcommand).with("help", [])
          command.execute("/worker conversation-summarizer")
        end

        it "returns :continue" do
          allow(worker_handler).to receive(:execute_subcommand).and_return(:continue)
          expect(command.execute("/worker conversation-summarizer")).to eq(:continue)
        end
      end

      context "with subcommand" do
        it "delegates to worker handler" do
          expect(worker_handler).to receive(:execute_subcommand).with("status", [])
          command.execute("/worker conversation-summarizer status")
        end

        it "passes additional arguments" do
          expect(worker_handler).to receive(:execute_subcommand).with("model", ["claude-opus-4-1"])
          command.execute("/worker conversation-summarizer model claude-opus-4-1")
        end

        it "returns :continue" do
          allow(worker_handler).to receive(:execute_subcommand).and_return(:continue)
          expect(command.execute("/worker conversation-summarizer on")).to eq(:continue)
        end
      end
    end

    context "when invalid worker name provided" do
      it "displays error message" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with(
          "Unknown worker: invalid-worker",
          type: :command
        )
        expect(application).to receive(:output_line).with(
          "Available workers: conversation-summarizer, exchange-summarizer, embeddings",
          type: :command
        )
        command.execute("/worker invalid-worker")
      end

      it "returns :continue" do
        expect(command.execute("/worker invalid-worker")).to eq(:continue)
      end
    end
  end

  describe "#create_worker_handler" do
    it "creates ConversationSummarizerCommand for conversation-summarizer" do
      handler = command.send(:create_worker_handler, "conversation-summarizer")
      expect(handler).to be_a(Nu::Agent::Commands::Workers::ConversationSummarizerCommand)
    end

    it "creates ExchangeSummarizerCommand for exchange-summarizer" do
      handler = command.send(:create_worker_handler, "exchange-summarizer")
      expect(handler).to be_a(Nu::Agent::Commands::Workers::ExchangeSummarizerCommand)
    end

    it "creates EmbeddingsCommand for embeddings" do
      handler = command.send(:create_worker_handler, "embeddings")
      expect(handler).to be_a(Nu::Agent::Commands::Workers::EmbeddingsCommand)
    end

    it "returns nil for unknown worker name" do
      handler = command.send(:create_worker_handler, "unknown-worker")
      expect(handler).to be_nil
    end
  end

  describe "#load_worker_verbosity" do
    it "loads conversation-summarizer verbosity from config" do
      allow(history).to receive(:get_int).with("conversation_summarizer_verbosity", default: 0).and_return(2)
      verbosity = command.send(:load_worker_verbosity, "conversation-summarizer")
      expect(verbosity).to eq(2)
    end

    it "loads exchange-summarizer verbosity from config" do
      allow(history).to receive(:get_int).with("exchange_summarizer_verbosity", default: 0).and_return(3)
      verbosity = command.send(:load_worker_verbosity, "exchange-summarizer")
      expect(verbosity).to eq(3)
    end

    it "loads embeddings verbosity from config" do
      allow(history).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(1)
      verbosity = command.send(:load_worker_verbosity, "embeddings")
      expect(verbosity).to eq(1)
    end

    it "returns 0 as default when not configured" do
      allow(history).to receive(:get_int).and_return(0)
      verbosity = command.send(:load_worker_verbosity, "conversation-summarizer")
      expect(verbosity).to eq(0)
    end
  end
end
