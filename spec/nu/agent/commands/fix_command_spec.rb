# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/fix_command"

RSpec.describe Nu::Agent::Commands::FixCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:command) { described_class.new(application) }

  describe "#execute" do
    it "calls run_fix on the application" do
      expect(application).to receive(:run_fix)
      command.execute("/fix")
    end

    it "returns :continue" do
      allow(application).to receive(:run_fix)
      expect(command.execute("/fix")).to eq(:continue)
    end
  end
end
