# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/command_registry"
require "nu/agent/commands/base_command"

RSpec.describe Nu::Agent::Commands::CommandRegistry do
  let(:registry) { described_class.new }
  let(:application) { instance_double("Nu::Agent::Application") }

  # Test command for registration
  let(:test_command_class) do
    Class.new(Nu::Agent::Commands::BaseCommand) do
      def execute(_input)
        :test_result
      end
    end
  end

  describe "#register" do
    it "registers a command class with a name" do
      registry.register("/test", test_command_class)
      expect(registry.registered?("/test")).to be true
    end

    it "allows registering multiple commands" do
      registry.register("/test1", test_command_class)
      registry.register("/test2", test_command_class)
      expect(registry.registered?("/test1")).to be true
      expect(registry.registered?("/test2")).to be true
    end
  end

  describe "#registered?" do
    it "returns false for unregistered commands" do
      expect(registry.registered?("/unknown")).to be false
    end

    it "returns true for registered commands" do
      registry.register("/test", test_command_class)
      expect(registry.registered?("/test")).to be true
    end
  end

  describe "#execute" do
    before do
      registry.register("/test", test_command_class)
    end

    it "executes a registered command" do
      result = registry.execute("/test", "/test", application)
      expect(result).to eq(:test_result)
    end

    it "returns :unknown for unregistered commands" do
      result = registry.execute("/unknown", "/unknown", application)
      expect(result).to eq(:unknown)
    end

    it "creates a new instance of the command class" do
      expect(test_command_class).to receive(:new).with(application).and_call_original
      registry.execute("/test", "/test", application)
    end

    it "passes the input to the command's execute method" do
      command_instance = test_command_class.new(application)
      allow(test_command_class).to receive(:new).and_return(command_instance)
      expect(command_instance).to receive(:execute).with("/test args")
      registry.execute("/test", "/test args", application)
    end
  end

  describe "#find" do
    before do
      registry.register("/test", test_command_class)
    end

    it "returns the command class for a registered command" do
      expect(registry.find("/test")).to eq(test_command_class)
    end

    it "returns nil for an unregistered command" do
      expect(registry.find("/unknown")).to be_nil
    end
  end
end
