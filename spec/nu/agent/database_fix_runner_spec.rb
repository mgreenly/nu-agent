# frozen_string_literal: true

require "spec_helper"
require "nu/agent/database_fix_runner"

RSpec.describe Nu::Agent::DatabaseFixRunner do
  let(:history) { double("history") }
  let(:console) { double("console") }
  let(:tui) { nil }
  let(:application) do
    double("application",
           history: history,
           console: console,
           tui: tui,
           output_line: nil)
  end

  describe ".run" do
    context "when no corruption is found" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:find_corrupted_messages).and_return([])
      end

      it "reports no corruption and returns early" do
        described_class.run(application)

        expect(application).to have_received(:output_line).with("Scanning database for corruption...",
type: :debug)
        expect(application).to have_received(:output_line).with("✓ No corruption found", type: :debug)
      end
    end

    context "when corruption is found" do
      let(:corrupted_messages) do
        [
          { "id" => 1, "tool_name" => "file_read", "created_at" => "2025-01-01" },
          { "id" => 2, "tool_name" => "execute_bash", "created_at" => "2025-01-02" }
        ]
      end

      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:find_corrupted_messages).and_return(corrupted_messages)
      end

      context "when user confirms deletion (using gets)" do
        before do
          allow(described_class).to receive(:gets).and_return("y\n")
          allow(history).to receive(:fix_corrupted_messages).with([1, 2]).and_return(2)
        end

        it "prompts user and deletes corrupted messages" do
          expect { described_class.run(application) }.to output(/Delete these messages/).to_stdout

          expect(history).to have_received(:fix_corrupted_messages).with([1, 2])
          expect(application).to have_received(:output_line).with("✓ Deleted 2 corrupted message(s)",
                                                                   type: :debug)
        end
      end

      context "when user declines deletion" do
        before do
          allow(described_class).to receive(:gets).and_return("n\n")
        end

        it "skips deletion" do
          expect { described_class.run(application) }.to output(/Delete these messages/).to_stdout

          expect(application).to have_received(:output_line).with("Skipped", type: :debug)
        end
      end

      context "when using TUI" do
        let(:tui) { double("tui", active: true, readline: "y") }

        before do
          allow(history).to receive(:fix_corrupted_messages).with([1, 2]).and_return(2)
        end

        it "uses TUI for prompting" do
          described_class.run(application)

          expect(tui).to have_received(:readline).with("Delete these messages? [y/N] ")
          expect(history).to have_received(:fix_corrupted_messages).with([1, 2])
        end
      end

      it "displays found corrupted messages" do
        allow(described_class).to receive(:gets).and_return("n\n")

        expect { described_class.run(application) }.to output.to_stdout

        expect(application).to have_received(:output_line).with("Found 2 corrupted message(s):", type: :debug)
        expect(application).to have_received(:output_line)
          .with("  • Message 1: file_read with redacted arguments (2025-01-01)", type: :debug)
        expect(application).to have_received(:output_line)
          .with("  • Message 2: execute_bash with redacted arguments (2025-01-02)", type: :debug)
      end
    end
  end
end
