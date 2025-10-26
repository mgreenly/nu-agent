# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/info_command"

RSpec.describe Nu::Agent::Commands::InfoCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:command) { described_class.new(application) }

  describe "#execute" do
    it "calls print_info on the application" do
      expect(application).to receive(:print_info)
      command.execute("/info")
    end

    it "returns :continue" do
      allow(application).to receive(:print_info)
      expect(command.execute("/info")).to eq(:continue)
    end
  end
end
