# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/workers/embeddings_command"

RSpec.describe Nu::Agent::Commands::Workers::EmbeddingsCommand do
  let(:application) { double("Nu::Agent::Application") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:worker_manager) { double("Nu::Agent::BackgroundWorkerManager") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(console: console, history: history, worker_manager: worker_manager)
    allow(application).to receive(:output_line)
    allow(application).to receive(:output_lines)
    allow(console).to receive(:puts)
  end

  describe "#execute_subcommand" do
    context "with 'help' subcommand" do
      it "displays worker-specific help" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_lines) do |*lines, type:|
          expect(type).to eq(:command)
          help_text = lines.join("\n")
          expect(help_text).to include("Embeddings Worker")
          expect(help_text).to include("/worker embeddings on|off")
          expect(help_text).to include("/worker embeddings batch")
          expect(help_text).to include("/worker embeddings rate")
        end
        command.execute_subcommand("help", [])
      end

      it "returns :continue" do
        expect(command.execute_subcommand("help", [])).to eq(:continue)
      end
    end

    context "with 'on' subcommand" do
      it "enables worker" do
        expect(history).to receive(:set_config).with("embeddings_enabled", "true")
        expect(worker_manager).to receive(:enable_worker).with("embeddings")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("embeddings=on", type: :command)
        command.execute_subcommand("on", [])
      end

      it "returns :continue" do
        allow(history).to receive(:set_config)
        allow(worker_manager).to receive(:enable_worker)
        expect(command.execute_subcommand("on", [])).to eq(:continue)
      end
    end

    context "with 'off' subcommand" do
      it "disables worker" do
        expect(history).to receive(:set_config).with("embeddings_enabled", "false")
        expect(worker_manager).to receive(:disable_worker).with("embeddings")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("embeddings=off", type: :command)
        command.execute_subcommand("off", [])
      end

      it "returns :continue" do
        allow(history).to receive(:set_config)
        allow(worker_manager).to receive(:disable_worker)
        expect(command.execute_subcommand("off", [])).to eq(:continue)
      end
    end

    context "with 'start' subcommand" do
      it "starts worker" do
        expect(worker_manager).to receive(:start_worker).with("embeddings")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Starting embeddings worker", type: :command)
        command.execute_subcommand("start", [])
      end

      it "returns :continue" do
        allow(worker_manager).to receive(:start_worker)
        expect(command.execute_subcommand("start", [])).to eq(:continue)
      end
    end

    context "with 'stop' subcommand" do
      it "stops worker" do
        expect(worker_manager).to receive(:stop_worker).with("embeddings")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Stopping embeddings worker", type: :command)
        command.execute_subcommand("stop", [])
      end

      it "returns :continue" do
        allow(worker_manager).to receive(:stop_worker)
        expect(command.execute_subcommand("stop", [])).to eq(:continue)
      end
    end

    context "with 'status' subcommand" do
      let(:status) do
        {
          "running" => true,
          "total" => 100,
          "completed" => 95,
          "failed" => 5,
          "spend" => 0.25
        }
      end

      before do
        allow(worker_manager).to receive(:worker_status).with("embeddings").and_return(status)
        allow(worker_manager).to receive(:worker_enabled?).with("embeddings").and_return(true)
        allow(history).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(2)
        allow(history).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(20)
        allow(history).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(150)
      end

      it "displays detailed worker status" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_lines) do |*lines, type:|
          expect(type).to eq(:command)
          status_text = lines.join("\n")
          expect(status_text).to include("Embeddings Worker Status:")
          expect(status_text).to include("Enabled: yes")
          expect(status_text).to include("State: running")
          expect(status_text).to include("Model: text-embedding-3-small (read-only)")
          expect(status_text).to include("Verbosity: 2")
          expect(status_text).to include("Batch size: 20")
          expect(status_text).to include("Rate limit: 150ms")
          expect(status_text).to include("Total processed: 100")
          expect(status_text).to include("Completed: 95")
          expect(status_text).to include("Failed: 5")
          expect(status_text).to include("Cost: $0.25")
        end
        command.execute_subcommand("status", [])
      end

      it "returns :continue" do
        expect(command.execute_subcommand("status", [])).to eq(:continue)
      end
    end

    context "with 'model' subcommand" do
      it "shows model is read-only" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with(
          "embeddings model: text-embedding-3-small (read-only)",
          type: :command
        )
        command.execute_subcommand("model", [])
      end

      it "returns :continue" do
        expect(command.execute_subcommand("model", [])).to eq(:continue)
      end
    end

    context "with 'verbosity' subcommand" do
      context "without level argument" do
        it "shows error" do
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "Usage: /worker embeddings verbosity <0-6>",
            type: :command
          )
          command.execute_subcommand("verbosity", [])
        end

        it "returns :continue" do
          expect(command.execute_subcommand("verbosity", [])).to eq(:continue)
        end
      end

      context "with valid level argument" do
        it "sets verbosity level" do
          expect(history).to receive(:set_config).with("embeddings_verbosity", "3")
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "embeddings verbosity: 3",
            type: :command
          )
          command.execute_subcommand("verbosity", ["3"])
        end

        it "returns :continue" do
          allow(history).to receive(:set_config)
          expect(command.execute_subcommand("verbosity", ["3"])).to eq(:continue)
        end
      end

      context "with invalid level argument" do
        it "shows error for non-numeric" do
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "Invalid verbosity level. Use 0-6.",
            type: :command
          )
          command.execute_subcommand("verbosity", ["invalid"])
        end

        it "shows error for out of range" do
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "Invalid verbosity level. Use 0-6.",
            type: :command
          )
          command.execute_subcommand("verbosity", ["10"])
        end

        it "returns :continue" do
          expect(command.execute_subcommand("verbosity", ["invalid"])).to eq(:continue)
        end
      end
    end

    context "with 'batch' subcommand" do
      context "without size argument" do
        it "shows current batch size" do
          allow(history).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(15)
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "embeddings batch size: 15",
            type: :command
          )
          command.execute_subcommand("batch", [])
        end

        it "returns :continue" do
          allow(history).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(15)
          expect(command.execute_subcommand("batch", [])).to eq(:continue)
        end
      end

      context "with valid size argument" do
        it "sets batch size" do
          expect(history).to receive(:set_config).with("embedding_batch_size", "25")
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "embeddings batch size: 25",
            type: :command
          )
          command.execute_subcommand("batch", ["25"])
        end

        it "returns :continue" do
          allow(history).to receive(:set_config)
          expect(command.execute_subcommand("batch", ["25"])).to eq(:continue)
        end
      end

      context "with invalid size argument" do
        it "shows error for non-numeric" do
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "Invalid batch size. Must be a positive integer.",
            type: :command
          )
          command.execute_subcommand("batch", ["invalid"])
        end

        it "shows error for non-positive" do
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "Invalid batch size. Must be a positive integer.",
            type: :command
          )
          command.execute_subcommand("batch", ["0"])
        end

        it "returns :continue" do
          expect(command.execute_subcommand("batch", ["invalid"])).to eq(:continue)
        end
      end
    end

    context "with 'rate' subcommand" do
      context "without limit argument" do
        it "shows current rate limit" do
          allow(history).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(200)
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "embeddings rate limit: 200ms",
            type: :command
          )
          command.execute_subcommand("rate", [])
        end

        it "returns :continue" do
          allow(history).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(200)
          expect(command.execute_subcommand("rate", [])).to eq(:continue)
        end
      end

      context "with valid limit argument" do
        it "sets rate limit" do
          expect(history).to receive(:set_config).with("embedding_rate_limit_ms", "300")
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "embeddings rate limit: 300ms",
            type: :command
          )
          command.execute_subcommand("rate", ["300"])
        end

        it "returns :continue" do
          allow(history).to receive(:set_config)
          expect(command.execute_subcommand("rate", ["300"])).to eq(:continue)
        end
      end

      context "with invalid limit argument" do
        it "shows error for non-numeric" do
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "Invalid rate limit. Must be a non-negative integer.",
            type: :command
          )
          command.execute_subcommand("rate", ["invalid"])
        end

        it "shows error for negative" do
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "Invalid rate limit. Must be a non-negative integer.",
            type: :command
          )
          command.execute_subcommand("rate", ["-1"])
        end

        it "returns :continue" do
          expect(command.execute_subcommand("rate", ["invalid"])).to eq(:continue)
        end
      end
    end

    context "with 'reset' subcommand" do
      it "clears all embeddings" do
        expect(history).to receive(:clear_all_embeddings)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with(
          "Cleared all embeddings",
          type: :command
        )
        command.execute_subcommand("reset", [])
      end

      it "returns :continue" do
        allow(history).to receive(:clear_all_embeddings)
        expect(command.execute_subcommand("reset", [])).to eq(:continue)
      end
    end

    context "with unknown subcommand" do
      it "shows error" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with(
          "Unknown subcommand: unknown",
          type: :command
        )
        expect(application).to receive(:output_line).with(
          "Use: /worker embeddings help",
          type: :command
        )
        command.execute_subcommand("unknown", [])
      end

      it "returns :continue" do
        expect(command.execute_subcommand("unknown", [])).to eq(:continue)
      end
    end
  end
end
