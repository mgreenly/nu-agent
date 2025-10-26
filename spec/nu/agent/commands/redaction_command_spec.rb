# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/redaction_command"

RSpec.describe Nu::Agent::Commands::RedactionCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive(:history).and_return(history)
    allow(application).to receive(:console).and_return(console)
    allow(application).to receive(:redact=)
    allow(application).to receive(:output_line)
    allow(history).to receive(:set_config)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    context "when no argument provided" do
      it "displays usage message" do
        allow(application).to receive(:redact).and_return(false)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Usage: /redaction <on|off>", type: :debug)
        expect(application).to receive(:output_line).with("Current: redaction=off", type: :debug)
        command.execute("/redaction")
      end

      it "returns :continue" do
        allow(application).to receive(:redact).and_return(false)
        expect(command.execute("/redaction")).to eq(:continue)
      end
    end

    context "when turning redaction on" do
      it "enables redaction mode" do
        expect(application).to receive(:redact=).with(true)
        expect(history).to receive(:set_config).with("redaction", "true")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("redaction=on", type: :debug)
        command.execute("/redaction on")
      end

      it "returns :continue" do
        expect(command.execute("/redaction on")).to eq(:continue)
      end
    end

    context "when turning redaction off" do
      it "disables redaction mode" do
        expect(application).to receive(:redact=).with(false)
        expect(history).to receive(:set_config).with("redaction", "false")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("redaction=off", type: :debug)
        command.execute("/redaction off")
      end

      it "returns :continue" do
        expect(command.execute("/redaction off")).to eq(:continue)
      end
    end

    context "when invalid argument provided" do
      it "displays error message" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Invalid option. Use: /redaction <on|off>", type: :debug)
        command.execute("/redaction invalid")
      end

      it "returns :continue" do
        expect(command.execute("/redaction invalid")).to eq(:continue)
      end
    end
  end
end
