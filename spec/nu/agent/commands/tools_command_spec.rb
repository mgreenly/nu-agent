# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/tools_command"

RSpec.describe Nu::Agent::Commands::ToolsCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:command) { described_class.new(application) }

  describe "#execute" do
    it "calls print_tools on the application" do
      expect(application).to receive(:print_tools)
      command.execute("/tools")
    end

    it "returns :continue" do
      allow(application).to receive(:print_tools)
      expect(command.execute("/tools")).to eq(:continue)
    end
  end
end
