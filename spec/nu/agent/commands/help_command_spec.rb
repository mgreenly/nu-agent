# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/help_command"

RSpec.describe Nu::Agent::Commands::HelpCommand do
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:application) { instance_double("Nu::Agent::Application", console: console) }
  let(:command) { described_class.new(application) }

  describe "#execute" do
    before do
      allow(console).to receive(:puts)
      allow(application).to receive(:output_lines)
    end

    it "prints a blank line to console" do
      expect(console).to receive(:puts).with("")
      command.execute("/help")
    end

    it "outputs help text using output_lines" do
      expect(application).to receive(:output_lines) do |*lines, type:|
        expect(type).to eq(:debug)
        expect(lines).to include(match(/Available commands/))
        expect(lines).to include(match(%r{/help.*Show this help message}))
      end
      command.execute("/help")
    end

    it "returns :continue" do
      expect(command.execute("/help")).to eq(:continue)
    end
  end
end
