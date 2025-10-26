# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/clear_command"

RSpec.describe Nu::Agent::Commands::ClearCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:command) { described_class.new(application) }

  describe "#execute" do
    it "calls clear_screen on the application" do
      expect(application).to receive(:clear_screen)
      command.execute("/clear")
    end

    it "returns :continue" do
      allow(application).to receive(:clear_screen)
      expect(command.execute("/clear")).to eq(:continue)
    end
  end
end
