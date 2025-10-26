# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/base_command"

RSpec.describe Nu::Agent::Commands::BaseCommand do
  let(:application) { instance_double("Nu::Agent::Application") }

  describe "#initialize" do
    it "stores the application instance" do
      command = described_class.new(application)
      expect(command.instance_variable_get(:@app)).to eq(application)
    end
  end

  describe "#execute" do
    it "raises NotImplementedError" do
      command = described_class.new(application)
      expect { command.execute("/test") }.to raise_error(NotImplementedError)
    end
  end
end
