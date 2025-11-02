# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/subsystems/subsystem_command"

RSpec.describe Nu::Agent::Commands::Subsystems::SubsystemCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:command) { described_class.new(application, "test", "test_verbosity") }

  before do
    allow(application).to receive_messages(history: history, console: console)
    allow(console).to receive(:puts)
    allow(application).to receive(:output_line)
  end

  describe ".description" do
    it "returns default description for subsystem commands" do
      expect(described_class.description).to eq("Manage subsystem debugging")
    end
  end

  describe "#initialize" do
    it "stores the application instance" do
      expect(command.instance_variable_get(:@app)).to eq(application)
    end

    it "stores the subsystem name" do
      expect(command.instance_variable_get(:@subsystem_name)).to eq("test")
    end

    it "stores the config key" do
      expect(command.instance_variable_get(:@config_key)).to eq("test_verbosity")
    end
  end

  describe "#execute" do
    context "with verbosity subcommand and no args" do
      it "shows current verbosity level" do
        allow(history).to receive(:get_int).with("test_verbosity", default: 0).and_return(2)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("test_verbosity=2", type: :command)
        result = command.execute("verbosity")
        expect(result).to eq(:continue)
      end

      it "defaults to 0 when not set" do
        allow(history).to receive(:get_int).with("test_verbosity", default: 0).and_return(0)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("test_verbosity=0", type: :command)
        result = command.execute("verbosity")
        expect(result).to eq(:continue)
      end
    end

    context "with verbosity subcommand and level argument" do
      it "sets verbosity level" do
        expect(history).to receive(:set_config).with("test_verbosity", "3")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("test_verbosity=3", type: :command)
        result = command.execute("verbosity 3")
        expect(result).to eq(:continue)
      end

      it "accepts level 0" do
        expect(history).to receive(:set_config).with("test_verbosity", "0")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("test_verbosity=0", type: :command)
        result = command.execute("verbosity 0")
        expect(result).to eq(:continue)
      end

      it "accepts high verbosity levels" do
        expect(history).to receive(:set_config).with("test_verbosity", "10")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("test_verbosity=10", type: :command)
        result = command.execute("verbosity 10")
        expect(result).to eq(:continue)
      end

      it "shows error for negative level" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Error: Level must be non-negative", type: :command)
        expect(application).to receive(:output_line).with("Usage: /test verbosity <level>", type: :command)
        result = command.execute("verbosity -1")
        expect(result).to eq(:continue)
      end

      it "shows error for non-numeric level" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Error: Level must be a number", type: :command)
        expect(application).to receive(:output_line).with("Usage: /test verbosity <level>", type: :command)
        result = command.execute("verbosity abc")
        expect(result).to eq(:continue)
      end
    end

    context "with help subcommand" do
      it "raises NotImplementedError" do
        expect { command.execute("help") }.to raise_error(NotImplementedError, "Subclasses must implement show_help")
      end
    end

    context "with empty subcommand" do
      it "raises NotImplementedError" do
        expect { command.execute("") }.to raise_error(NotImplementedError, "Subclasses must implement show_help")
      end
    end

    context "with unknown subcommand" do
      it "shows error message" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Unknown subcommand: unknown", type: :command)
        expect(application).to receive(:output_line).with("Use: /test help", type: :command)
        result = command.execute("unknown")
        expect(result).to eq(:continue)
      end
    end

    context "with verbosity and extra spaces" do
      it "handles extra whitespace correctly" do
        expect(history).to receive(:set_config).with("test_verbosity", "2")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("test_verbosity=2", type: :command)
        result = command.execute("  verbosity   2  ")
        expect(result).to eq(:continue)
      end
    end

    context "with command prefix" do
      it "strips command prefix before processing" do
        allow(history).to receive(:get_int).with("test_verbosity", default: 0).and_return(1)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("test_verbosity=1", type: :command)
        result = command.execute("/test verbosity")
        expect(result).to eq(:continue)
      end

      it "handles prefix with arguments" do
        expect(history).to receive(:set_config).with("test_verbosity", "5")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("test_verbosity=5", type: :command)
        result = command.execute("/test verbosity 5")
        expect(result).to eq(:continue)
      end
    end
  end
end
