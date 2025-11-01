# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/subsystems/llm_command"

RSpec.describe Nu::Agent::Commands::Subsystems::LlmCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(history: history, console: console)
    allow(console).to receive(:puts)
    allow(application).to receive(:output_line)
    allow(application).to receive(:output_lines)
  end

  describe "#initialize" do
    it "initializes with correct subsystem name and config key" do
      expect(command.instance_variable_get(:@subsystem_name)).to eq("llm")
      expect(command.instance_variable_get(:@config_key)).to eq("llm_verbosity")
    end
  end

  describe "#execute" do
    context "with verbosity subcommand" do
      it "shows current verbosity" do
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(3)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("llm_verbosity=3", type: :command)
        result = command.execute("verbosity")
        expect(result).to eq(:continue)
      end

      it "sets verbosity level" do
        expect(history).to receive(:set_config).with("llm_verbosity", "2")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("llm_verbosity=2", type: :command)
        result = command.execute("verbosity 2")
        expect(result).to eq(:continue)
      end
    end

    context "with help subcommand" do
      it "displays help text" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_lines) do |*lines|
          expect(lines.flatten).to include("LLM Subsystem")
          expect(lines.flatten).to include("Commands:")
          expect(lines.flatten).to include("Verbosity Levels:")
          expect(lines.flatten.any? { |line| line.include?("0 - No LLM debug output") }).to be true
          expect(lines.flatten.any? { |line| line.include?("1 - Show warnings") }).to be true
          expect(lines.flatten.any? { |line| line.include?("2 - Show message count") }).to be true
        end
        result = command.execute("help")
        expect(result).to eq(:continue)
      end
    end

    context "with empty input" do
      it "displays help text" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_lines)
        result = command.execute("")
        expect(result).to eq(:continue)
      end
    end
  end
end
