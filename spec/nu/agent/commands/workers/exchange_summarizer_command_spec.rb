# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/workers/exchange_summarizer_command"

RSpec.describe Nu::Agent::Commands::Workers::ExchangeSummarizerCommand do
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
          expect(help_text).to include("Exchange Summarizer Worker")
          expect(help_text).to include("/worker exchange-summarizer on|off")
          expect(help_text).to include("/worker exchange-summarizer status")
          expect(help_text).to include("Verbosity Levels")
        end
        command.execute_subcommand("help", [])
      end

      it "returns :continue" do
        expect(command.execute_subcommand("help", [])).to eq(:continue)
      end
    end

    context "with 'on' subcommand" do
      it "enables worker" do
        expect(history).to receive(:set_config).with("exchange_summarizer_enabled", "true")
        expect(worker_manager).to receive(:enable_worker).with("exchange-summarizer")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("exchange-summarizer=on", type: :command)
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
        expect(history).to receive(:set_config).with("exchange_summarizer_enabled", "false")
        expect(worker_manager).to receive(:disable_worker).with("exchange-summarizer")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("exchange-summarizer=off", type: :command)
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
        expect(worker_manager).to receive(:start_worker).with("exchange-summarizer")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Starting exchange-summarizer worker", type: :command)
        command.execute_subcommand("start", [])
      end

      it "returns :continue" do
        allow(worker_manager).to receive(:start_worker)
        expect(command.execute_subcommand("start", [])).to eq(:continue)
      end
    end

    context "with 'stop' subcommand" do
      it "stops worker" do
        expect(worker_manager).to receive(:stop_worker).with("exchange-summarizer")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Stopping exchange-summarizer worker", type: :command)
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
          "total" => 42,
          "completed" => 40,
          "failed" => 2,
          "spend" => 0.15
        }
      end

      before do
        allow(worker_manager).to receive(:worker_status).with("exchange-summarizer").and_return(status)
        allow(worker_manager).to receive(:worker_enabled?).with("exchange-summarizer").and_return(true)
        allow(worker_manager).to receive(:worker_metrics).with("exchange-summarizer").and_return(nil)
        allow(history).to receive(:get_config).with("exchange_summarizer_model").and_return("claude-sonnet-4-5")
        allow(history).to receive(:get_int).with("exchange_summarizer_verbosity", 0).and_return(1)
      end

      it "displays detailed worker status" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_lines) do |*lines, type:|
          expect(type).to eq(:command)
          status_text = lines.join("\n")
          expect(status_text).to include("Exchange Summarizer Status:")
          expect(status_text).to include("Enabled: yes")
          expect(status_text).to include("State: running")
          expect(status_text).to include("Model: claude-sonnet-4-5")
          expect(status_text).to include("Verbosity: 1")
          expect(status_text).to include("Total processed: 42")
          expect(status_text).to include("Completed: 40")
          expect(status_text).to include("Failed: 2")
          expect(status_text).to include("Cost: $0.15")
        end
        command.execute_subcommand("status", [])
      end

      it "returns :continue" do
        expect(command.execute_subcommand("status", [])).to eq(:continue)
      end

      context "with metrics" do
        let(:metrics_collector) { instance_double(Nu::Agent::MetricsCollector) }

        before do
          allow(worker_manager).to receive(:worker_metrics).with("exchange-summarizer").and_return(metrics_collector)
          allow(metrics_collector).to receive(:get_timer_stats).with(:exchange_processing).and_return(
            { count: 40, p50: 125.5, p90: 250.2, p99: 450.8 }
          )
        end

        it "includes metrics in status output" do
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_lines) do |*lines, type:|
            expect(type).to eq(:command)
            status_text = lines.join("\n")
            expect(status_text).to include("Performance Metrics:")
            expect(status_text).to include("Processing latency (p50): 125.5ms")
            expect(status_text).to include("Processing latency (p90): 250.2ms")
            expect(status_text).to include("Processing latency (p99): 450.8ms")
          end
          command.execute_subcommand("status", [])
        end

        context "when no metrics recorded yet" do
          before do
            allow(metrics_collector).to receive(:get_timer_stats).with(:exchange_processing).and_return(
              { count: 0, p50: 0, p90: 0, p99: 0 }
            )
          end

          it "does not include metrics section" do
            expect(console).to receive(:puts).with("")
            expect(application).to receive(:output_lines) do |*lines, type:|
              expect(type).to eq(:command)
              status_text = lines.join("\n")
              expect(status_text).not_to include("Performance Metrics:")
            end
            command.execute_subcommand("status", [])
          end
        end
      end
    end

    context "with 'model' subcommand" do
      context "without model argument" do
        it "shows current model" do
          allow(history).to receive(:get_config).with("exchange_summarizer_model").and_return("claude-sonnet-4-5")
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "exchange-summarizer model: claude-sonnet-4-5",
            type: :command
          )
          command.execute_subcommand("model", [])
        end

        it "returns :continue" do
          allow(history).to receive(:get_config).with("exchange_summarizer_model").and_return("claude-sonnet-4-5")
          expect(command.execute_subcommand("model", [])).to eq(:continue)
        end
      end

      context "with model argument" do
        it "changes model" do
          expect(history).to receive(:set_config).with("exchange_summarizer_model", "claude-opus-4-1")
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "exchange-summarizer model: claude-opus-4-1",
            type: :command
          )
          expect(application).to receive(:output_line).with(
            "Model will be used on next /reset",
            type: :command
          )
          command.execute_subcommand("model", ["claude-opus-4-1"])
        end

        it "returns :continue" do
          allow(history).to receive(:set_config)
          expect(command.execute_subcommand("model", ["claude-opus-4-1"])).to eq(:continue)
        end
      end
    end

    context "with 'verbosity' subcommand" do
      context "without level argument" do
        it "shows error" do
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "Usage: /worker exchange-summarizer verbosity <0-6>",
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
          expect(history).to receive(:set_config).with("exchange_summarizer_verbosity", "2")
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with(
            "exchange-summarizer verbosity: 2",
            type: :command
          )
          command.execute_subcommand("verbosity", ["2"])
        end

        it "returns :continue" do
          allow(history).to receive(:set_config)
          expect(command.execute_subcommand("verbosity", ["2"])).to eq(:continue)
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
          command.execute_subcommand("verbosity", ["7"])
        end

        it "returns :continue" do
          expect(command.execute_subcommand("verbosity", ["invalid"])).to eq(:continue)
        end
      end
    end

    context "with 'reset' subcommand" do
      it "clears exchange summaries" do
        expect(history).to receive(:clear_conversation_summaries)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with(
          "Cleared all exchange summaries",
          type: :command
        )
        command.execute_subcommand("reset", [])
      end

      it "returns :continue" do
        allow(history).to receive(:clear_conversation_summaries)
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
          "Use: /worker exchange-summarizer help",
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
