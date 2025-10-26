# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/exit_command"

RSpec.describe Nu::Agent::Commands::ExitCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:command) { described_class.new(application) }

  describe "#execute" do
    it "returns :exit" do
      expect(command.execute("/exit")).to eq(:exit)
    end
  end
end
