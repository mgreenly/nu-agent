# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/spellcheck_command"

RSpec.describe Nu::Agent::Commands::SpellcheckCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive(:history).and_return(history)
    allow(application).to receive(:console).and_return(console)
    allow(application).to receive(:spell_check_enabled=)
    allow(application).to receive(:output_line)
    allow(history).to receive(:set_config)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    context "when no argument provided" do
      it "displays usage message" do
        allow(application).to receive(:spell_check_enabled).and_return(false)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Usage: /spellcheck <on|off>", type: :debug)
        expect(application).to receive(:output_line).with("Current: spellcheck=off", type: :debug)
        command.execute("/spellcheck")
      end

      it "returns :continue" do
        allow(application).to receive(:spell_check_enabled).and_return(false)
        expect(command.execute("/spellcheck")).to eq(:continue)
      end
    end

    context "when turning spellcheck on" do
      it "enables spellcheck mode" do
        expect(application).to receive(:spell_check_enabled=).with(true)
        expect(history).to receive(:set_config).with("spell_check_enabled", "true")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("spellcheck=on", type: :debug)
        command.execute("/spellcheck on")
      end

      it "returns :continue" do
        expect(command.execute("/spellcheck on")).to eq(:continue)
      end
    end

    context "when turning spellcheck off" do
      it "disables spellcheck mode" do
        expect(application).to receive(:spell_check_enabled=).with(false)
        expect(history).to receive(:set_config).with("spell_check_enabled", "false")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("spellcheck=off", type: :debug)
        command.execute("/spellcheck off")
      end

      it "returns :continue" do
        expect(command.execute("/spellcheck off")).to eq(:continue)
      end
    end

    context "when invalid argument provided" do
      it "displays error message" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Invalid option. Use: /spellcheck <on|off>", type: :debug)
        command.execute("/spellcheck invalid")
      end

      it "returns :continue" do
        expect(command.execute("/spellcheck invalid")).to eq(:continue)
      end
    end
  end
end
