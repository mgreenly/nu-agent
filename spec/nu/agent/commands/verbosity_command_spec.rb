# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/verbosity_command"

RSpec.describe Nu::Agent::Commands::VerbosityCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(console: console)
    allow(application).to receive(:output_line)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    it "shows deprecation message" do
      expect(console).to receive(:puts).with("")
      expect(application).to receive(:output_line).with("The /verbosity command is deprecated.", type: :command)
      expect(application).to receive(:output_line).with("Please use subsystem-specific commands instead:",
                                                        type: :command)
      expect(application).to receive(:output_line).with("", type: :command)
      expect(application).to receive(:output_line).with("  /llm verbosity <level>        - LLM debug output",
                                                        type: :command)
      expect(application).to receive(:output_line).with("  /tools-debug verbosity <level> - Tool debug output",
                                                        type: :command)
      expect(application).to receive(:output_line).with("  /messages verbosity <level>   - Message tracking",
                                                        type: :command)
      expect(application).to receive(:output_line).with("  /search verbosity <level>     - Search internals",
                                                        type: :command)
      expect(application).to receive(:output_line).with("  /stats verbosity <level>      - Statistics/costs",
                                                        type: :command)
      expect(application).to receive(:output_line).with("  /spellcheck-debug verbosity <level> - Spell checker",
                                                        type: :command)
      expect(application).to receive(:output_line).with("", type: :command)
      expect(application).to receive(:output_line)
        .with("Use /<subsystem> help to see verbosity levels for each subsystem.", type: :command)

      command.execute("/verbosity")
    end

    it "returns :continue" do
      expect(command.execute("/verbosity")).to eq(:continue)
    end

    it "ignores any arguments and shows deprecation message" do
      expect(console).to receive(:puts).with("")
      expect(application).to receive(:output_line).at_least(:once)

      command.execute("/verbosity 3")
    end
  end
end
