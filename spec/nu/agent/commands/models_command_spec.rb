# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/models_command"

RSpec.describe Nu::Agent::Commands::ModelsCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:command) { described_class.new(application) }

  describe "#execute" do
    it "calls print_models on the application" do
      expect(application).to receive(:print_models)
      command.execute("/models")
    end

    it "returns :continue" do
      allow(application).to receive(:print_models)
      expect(command.execute("/models")).to eq(:continue)
    end
  end
end
