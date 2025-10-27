# frozen_string_literal: true

require "spec_helper"
require "nu/agent/exchange_migration_runner"

RSpec.describe Nu::Agent::ExchangeMigrationRunner do
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
    before do
      allow(console).to receive(:puts)
    end

    context "when user confirms migration (using gets)" do
      let(:migration_stats) do
        {
          conversations: 10,
          exchanges_created: 25,
          messages_updated: 50
        }
      end

      before do
        allow(described_class).to receive(:gets).and_return("y\n")
        allow(history).to receive(:migrate_exchanges).and_return(migration_stats)
      end

      it "prompts user and runs migration" do
        expect { described_class.run(application) }.to output(/Continue with migration/).to_stdout

        expect(history).to have_received(:migrate_exchanges)
        expect(application).to have_received(:output_line).with("Migrating exchanges...", type: :debug)
        expect(application).to have_received(:output_line).with("Migration complete!", type: :debug)
      end

      it "displays migration statistics" do
        expect { described_class.run(application) }.to output.to_stdout

        expect(application).to have_received(:output_line).with("  Conversations processed: 10", type: :debug)
        expect(application).to have_received(:output_line).with("  Exchanges created: 25", type: :debug)
        expect(application).to have_received(:output_line).with("  Messages updated: 50", type: :debug)
      end

      it "displays elapsed time" do
        expect { described_class.run(application) }.to output.to_stdout

        expect(application).to have_received(:output_line).with(a_string_matching(/Time elapsed: \d+\.\d+s/),
                                                                type: :debug)
      end
    end

    context "when user declines migration" do
      before do
        allow(described_class).to receive(:gets).and_return("n\n")
      end

      it "returns early without migrating" do
        expect { described_class.run(application) }.to output(/Continue with migration/).to_stdout

        expect(application).to have_received(:output_line)
          .with("This will analyze all messages and group them into exchanges.", type: :debug)
        expect(application).to have_received(:output_line)
          .with("Existing exchanges will NOT be affected.", type: :debug)
        expect(application).not_to have_received(:output_line).with("Migrating exchanges...", type: :debug)
      end
    end

    context "when using TUI" do
      let(:tui) { double("tui", active: true, readline: "y") }
      let(:migration_stats) { { conversations: 5, exchanges_created: 10, messages_updated: 20 } }

      before do
        allow(history).to receive(:migrate_exchanges).and_return(migration_stats)
      end

      it "uses TUI for prompting" do
        described_class.run(application)

        expect(tui).to have_received(:readline).with("Continue with migration? [y/N] ")
        expect(history).to have_received(:migrate_exchanges)
      end
    end
  end
end
