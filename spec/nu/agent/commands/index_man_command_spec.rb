# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/index_man_command"

RSpec.describe Nu::Agent::Commands::IndexManCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:status_mutex) { Mutex.new }
  let(:man_indexer_status) do
    {
      "running" => false,
      "total" => 100,
      "completed" => 0,
      "failed" => 0,
      "skipped" => 0,
      "session_spend" => 0.0,
      "session_tokens" => 0
    }
  end
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive(:console).and_return(console)
    allow(application).to receive(:history).and_return(history)
    allow(application).to receive(:status_mutex).and_return(status_mutex)
    allow(application).to receive(:man_indexer_status).and_return(man_indexer_status)
    allow(application).to receive(:output_line)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    context "when called without arguments or with empty argument" do
      it "shows usage and current status" do
        allow(history).to receive(:get_config).with("index_man_enabled").and_return("false")

        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Usage: /index-man <on|off|reset>", type: :debug)
        expect(application).to receive(:output_line).with("Current: index-man=off", type: :debug)

        result = command.execute("/index-man")
        expect(result).to eq(:continue)
      end

      it "shows current status when enabled" do
        allow(history).to receive(:get_config).with("index_man_enabled").and_return("true")

        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Usage: /index-man <on|off|reset>", type: :debug)
        expect(application).to receive(:output_line).with("Current: index-man=on", type: :debug)

        command.execute("/index-man")
      end

      context "when indexer is running" do
        before do
          allow(history).to receive(:get_config).with("index_man_enabled").and_return("true")
          man_indexer_status["running"] = true
          man_indexer_status["completed"] = 25
          man_indexer_status["failed"] = 2
          man_indexer_status["skipped"] = 3
          man_indexer_status["session_spend"] = 0.123456
        end

        it "shows running status" do
          expect(application).to receive(:output_line).with("Status: running (25/100 man pages)", type: :debug)
          expect(application).to receive(:output_line).with("Failed: 2, Skipped: 3", type: :debug)
          expect(application).to receive(:output_line).with("Session spend: $0.123456", type: :debug)

          command.execute("/index-man")
        end
      end

      context "when indexer has completed" do
        before do
          allow(history).to receive(:get_config).with("index_man_enabled").and_return("false")
          man_indexer_status["running"] = false
          man_indexer_status["total"] = 100
          man_indexer_status["completed"] = 95
          man_indexer_status["failed"] = 3
          man_indexer_status["skipped"] = 2
          man_indexer_status["session_spend"] = 1.234567
        end

        it "shows completed status" do
          expect(application).to receive(:output_line).with("Status: completed (95/100 man pages)", type: :debug)
          expect(application).to receive(:output_line).with("Failed: 3, Skipped: 2", type: :debug)
          expect(application).to receive(:output_line).with("Session spend: $1.234567", type: :debug)

          command.execute("/index-man")
        end
      end
    end

    context "when turning on" do
      before do
        allow(history).to receive(:set_config)
        allow(application).to receive(:start_man_indexer_worker)
      end

      it "enables indexing and starts worker" do
        expect(history).to receive(:set_config).with("index_man_enabled", "true")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("index-man=on", type: :debug)
        expect(application).to receive(:output_line).with("Starting man page indexer...", type: :debug)
        expect(application).to receive(:start_man_indexer_worker)

        result = command.execute("/index-man on")
        expect(result).to eq(:continue)
      end

      it "shows initial status after starting" do
        man_indexer_status["total"] = 150

        expect(application).to receive(:output_line).with("Indexing 150 man pages...", type: :debug)
        expect(application).to receive(:output_line).with(/This will take approximately \d+ minutes/, type: :debug)

        command.execute("/index-man on")
      end
    end

    context "when turning off" do
      before do
        allow(history).to receive(:set_config)
      end

      it "disables indexing" do
        expect(history).to receive(:set_config).with("index_man_enabled", "false")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("index-man=off", type: :debug)
        expect(application).to receive(:output_line)
          .with("Indexer will stop after current batch completes", type: :debug)

        result = command.execute("/index-man off")
        expect(result).to eq(:continue)
      end

      context "when there are indexed pages" do
        before do
          man_indexer_status["completed"] = 50
          man_indexer_status["total"] = 100
          man_indexer_status["failed"] = 3
          man_indexer_status["skipped"] = 2
          man_indexer_status["session_spend"] = 0.456789
        end

        it "shows final status" do
          expect(application).to receive(:output_line).with("Indexed: 50/100 man pages", type: :debug)
          expect(application).to receive(:output_line).with("Failed: 3, Skipped: 2", type: :debug)
          expect(application).to receive(:output_line).with("Session spend: $0.456789", type: :debug)

          command.execute("/index-man off")
        end
      end
    end

    context "when resetting" do
      let(:embedding_stats) { [{ "kind" => "man_page", "count" => 250 }] }

      before do
        allow(history).to receive(:get_config).with("index_man_enabled").and_return("false")
        allow(history).to receive(:set_config)
        allow(history).to receive(:embedding_stats).with(kind: "man_page").and_return(embedding_stats)
        allow(history).to receive(:clear_embeddings)
      end

      it "clears embeddings and resets status" do
        expect(history).to receive(:clear_embeddings).with(kind: "man_page")
        expect(application).to receive(:output_line).with("Reset complete: Cleared 250 man page embeddings", type: :debug)

        command.execute("/index-man reset")
      end

      it "resets all status counters" do
        command.execute("/index-man reset")

        expect(man_indexer_status["total"]).to eq(0)
        expect(man_indexer_status["completed"]).to eq(0)
        expect(man_indexer_status["failed"]).to eq(0)
        expect(man_indexer_status["skipped"]).to eq(0)
        expect(man_indexer_status["session_spend"]).to eq(0.0)
        expect(man_indexer_status["session_tokens"]).to eq(0)
      end

      context "when indexer is running" do
        before do
          allow(history).to receive(:get_config).with("index_man_enabled").and_return("true")
        end

        it "stops indexer before resetting" do
          expect(history).to receive(:set_config).with("index_man_enabled", "false")
          expect(console).to receive(:puts).with("")
          expect(application).to receive(:output_line).with("Stopping indexer before reset...", type: :debug)

          command.execute("/index-man reset")
        end
      end

      context "when no embeddings exist" do
        let(:embedding_stats) { [] }

        it "handles zero count gracefully" do
          expect(application).to receive(:output_line).with("Reset complete: Cleared 0 man page embeddings", type: :debug)

          command.execute("/index-man reset")
        end
      end
    end

    context "when using invalid option" do
      before do
        allow(history).to receive(:get_config).with("index_man_enabled").and_return("false")
      end

      it "shows error message" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Invalid option. Use: /index-man <on|off|reset>", type: :debug)

        result = command.execute("/index-man invalid")
        expect(result).to eq(:continue)
      end
    end
  end
end
