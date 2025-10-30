# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/worker_command"

RSpec.describe Nu::Agent::Commands::WorkerCommand do
  let(:application) { double("Nu::Agent::Application") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:worker_manager) { instance_double("Nu::Agent::BackgroundWorkerManager") }
  let(:worker_registry) { {} }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(console: console, worker_manager: worker_manager,
                                           worker_registry: worker_registry)
    allow(application).to receive(:output_line)
    allow(application).to receive(:output_lines)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    context "when no argument provided" do
      it "displays general help" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_lines) do |*lines, type:|
          expect(type).to eq(:debug)
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
          expect(type).to eq(:debug)
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
          expect(type).to eq(:debug)
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
        worker_registry["conversation-summarizer"] = worker_handler
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
          type: :debug
        )
        expect(application).to receive(:output_line).with(
          "Available workers: conversation-summarizer, exchange-summarizer, embeddings",
          type: :debug
        )
        command.execute("/worker invalid-worker")
      end

      it "returns :continue" do
        expect(command.execute("/worker invalid-worker")).to eq(:continue)
      end
    end
  end
end
