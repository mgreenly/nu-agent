# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/verbosity_command"

RSpec.describe Nu::Agent::Commands::VerbosityCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(console: console, history: history)
    allow(application).to receive(:output_line)
    allow(console).to receive(:puts)
    allow(history).to receive(:get_int).and_return(0)
    allow(history).to receive(:set_config)
  end

  describe "#execute" do
    context "with no arguments" do
      it "shows all subsystems with their current levels" do
        allow(history).to receive(:get_int).with("console_verbosity", default: 0).and_return(0)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(2)
        allow(history).to receive(:get_int).with("messages_verbosity", default: 0).and_return(1)
        allow(history).to receive(:get_int).with("search_verbosity", default: 0).and_return(0)
        allow(history).to receive(:get_int).with("stats_verbosity", default: 0).and_return(0)
        allow(history).to receive(:get_int).with("thread_verbosity", default: 0).and_return(0)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(3)

        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("/verbosity console (0-1) = 0", type: :command)
        expect(application).to receive(:output_line).with("/verbosity llm (0-5) = 2", type: :command)
        expect(application).to receive(:output_line).with("/verbosity messages (0-3) = 1", type: :command)
        expect(application).to receive(:output_line).with("/verbosity search (0-2) = 0", type: :command)
        expect(application).to receive(:output_line).with("/verbosity stats (0-2) = 0", type: :command)
        expect(application).to receive(:output_line).with("/verbosity thread (0-1) = 0", type: :command)
        expect(application).to receive(:output_line).with("/verbosity tools (0-3) = 3", type: :command)

        command.execute("/verbosity")
      end

      it "returns :continue" do
        expect(command.execute("/verbosity")).to eq(:continue)
      end
    end

    context "with 'help' argument" do
      # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
      it "shows detailed help with all subsystems and levels" do
        expect(console).to receive(:puts).with("")

        # Header
        expect(application).to receive(:output_line).with("Subsystem Verbosity Control", type: :command)
        expect(application).to receive(:output_line).with("", type: :command)

        # Usage
        expect(application).to receive(:output_line).with("Usage:", type: :command)
        expect(application).to receive(:output_line)
          .with("  /verbosity                    - Show all subsystem levels", type: :command)
        expect(application).to receive(:output_line)
          .with("  /verbosity <subsystem>        - Show specific subsystem level", type: :command)
        expect(application).to receive(:output_line)
          .with("  /verbosity <subsystem> <level> - Set subsystem level", type: :command)
        expect(application).to receive(:output_line).with("  /verbosity help               - Show this help",
                                                          type: :command)
        expect(application).to receive(:output_line).with("", type: :command)

        # Available subsystems header
        expect(application).to receive(:output_line).with("Available subsystems:", type: :command)
        expect(application).to receive(:output_line).with("", type: :command)

        # llm subsystem - all levels
        expect(application).to receive(:output_line).with("llm (0-5):", type: :command)
        expect(application).to receive(:output_line).with("  0: No LLM debug output", type: :command)
        expect(application).to receive(:output_line)
          .with("  1: Show final user message only", type: :command)
        expect(application).to receive(:output_line)
          .with("  2: Show final user message + system prompt", type: :command)
        expect(application).to receive(:output_line)
          .with("  3: Show final user message + system prompt + RAG content (redactions, spell check)",
                type: :command)
        expect(application).to receive(:output_line)
          .with("  4: Show final user message + system prompt + RAG content + tool definitions", type: :command)
        expect(application).to receive(:output_line)
          .with("  5: Show final user message + system prompt + RAG content + tool definitions + " \
                "complete message history", type: :command)
        expect(application).to receive(:output_line).with("", type: :command)

        # messages subsystem - all levels
        expect(application).to receive(:output_line).with("messages (0-3):", type: :command)
        expect(application).to receive(:output_line).with("  0: No message tracking output", type: :command)
        expect(application).to receive(:output_line)
          .with("  1: Basic message in/out notifications", type: :command)
        expect(application).to receive(:output_line)
          .with("  2: Add role, actor, content preview (30 chars)", type: :command)
        expect(application).to receive(:output_line).with("  3: Extended previews (100 chars)", type: :command)
        expect(application).to receive(:output_line).with("", type: :command)

        # search subsystem - all levels
        expect(application).to receive(:output_line).with("search (0-2):", type: :command)
        expect(application).to receive(:output_line).with("  0: No search debug output", type: :command)
        expect(application).to receive(:output_line)
          .with("  1: Show search commands being executed", type: :command)
        expect(application).to receive(:output_line)
          .with("  2: Add search stats (files searched, matches found)", type: :command)
        expect(application).to receive(:output_line).with("", type: :command)

        # stats subsystem - all levels
        expect(application).to receive(:output_line).with("stats (0-2):", type: :command)
        expect(application).to receive(:output_line).with("  0: No statistics output", type: :command)
        expect(application).to receive(:output_line).with("  1: Show basic token/cost summary", type: :command)
        expect(application).to receive(:output_line)
          .with("  2: Add timing, cache hit rates, detailed breakdown", type: :command)
        expect(application).to receive(:output_line).with("", type: :command)

        # tools subsystem - all levels
        expect(application).to receive(:output_line).with("tools (0-3):", type: :command)
        expect(application).to receive(:output_line).with("  0: No tool debug output", type: :command)
        expect(application).to receive(:output_line).with("  1: Show tool name only", type: :command)
        expect(application).to receive(:output_line)
          .with("  2: Show tool name with brief arguments/results (truncated)", type: :command)
        expect(application).to receive(:output_line).with("  3: Show full arguments and full results", type: :command)
        expect(application).to receive(:output_line).with("", type: :command)

        command.execute("/verbosity help")
      end
      # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
    end

    context "with subsystem argument only" do
      it "shows the current verbosity level for that subsystem" do
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(2)

        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("/verbosity llm (0-5) = 2", type: :command)

        command.execute("/verbosity llm")
      end

      it "handles unknown subsystem" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Unknown subsystem: unknown", type: :command)
        expect(application).to receive(:output_line)
          .with("Available subsystems: console, llm, messages, search, stats, thread, tools",
                type: :command)
        expect(application).to receive(:output_line).with("Use: /verbosity help", type: :command)

        command.execute("/verbosity unknown")
      end
    end

    context "with subsystem and level arguments" do
      it "sets the verbosity level for the subsystem" do
        expect(history).to receive(:set_config).with("llm_verbosity", "3")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("llm_verbosity=3", type: :command)

        command.execute("/verbosity llm 3")
      end

      it "accepts level 0" do
        expect(history).to receive(:set_config).with("tools_verbosity", "0")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("tools_verbosity=0", type: :command)

        command.execute("/verbosity tools 0")
      end

      it "accepts high verbosity levels" do
        expect(history).to receive(:set_config).with("messages_verbosity", "10")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("messages_verbosity=10", type: :command)

        command.execute("/verbosity messages 10")
      end

      it "rejects negative levels" do
        expect(history).not_to receive(:set_config)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Error: Level must be non-negative", type: :command)
        expect(application).to receive(:output_line).with("Usage:", type: :command)
        expect(application).to receive(:output_line).at_least(:once)

        command.execute("/verbosity llm -1")
      end

      it "rejects non-numeric levels" do
        expect(history).not_to receive(:set_config)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Error: Level must be a number", type: :command)
        expect(application).to receive(:output_line).with("Usage:", type: :command)
        expect(application).to receive(:output_line).at_least(:once)

        command.execute("/verbosity llm abc")
      end

      it "handles unknown subsystem when setting level" do
        expect(history).not_to receive(:set_config)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Unknown subsystem: unknown", type: :command)
        expect(application).to receive(:output_line)
          .with("Available subsystems: console, llm, messages, search, stats, thread, tools",
                type: :command)
        expect(application).to receive(:output_line).with("Use: /verbosity help", type: :command)

        command.execute("/verbosity unknown 2")
      end
    end

    context "with too many arguments" do
      it "shows error and usage" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Usage:", type: :command)
        expect(application).to receive(:output_line)
          .with("  /verbosity                    - Show all subsystem levels", type: :command)
        expect(application).to receive(:output_line)
          .with("  /verbosity <subsystem>        - Show specific subsystem level", type: :command)
        expect(application).to receive(:output_line)
          .with("  /verbosity <subsystem> <level> - Set subsystem level", type: :command)
        expect(application).to receive(:output_line).with("  /verbosity help               - Show detailed help",
                                                          type: :command)

        command.execute("/verbosity llm 2 extra")
      end
    end

    context "persistence" do
      it "saves config with correct key format" do
        expect(history).to receive(:set_config).with("stats_verbosity", "1")

        command.execute("/verbosity stats 1")
      end
    end
  end
end
