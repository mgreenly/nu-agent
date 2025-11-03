# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/summarizer_command"

RSpec.describe Nu::Agent::Commands::SummarizerCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(history: history, console: console)
    allow(application).to receive(:summarizer_enabled=)
    allow(application).to receive(:output_line)
    allow(history).to receive(:set_config)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    context "when no argument provided" do
      it "displays usage message with summarizer off" do
        allow(application).to receive(:summarizer_enabled).and_return(false)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Usage: /summarizer <on|off>", type: :command)
        expect(application).to receive(:output_line).with("Current: summarizer=off", type: :command)
        command.execute("/summarizer")
      end

      it "displays usage message with summarizer on" do
        allow(application).to receive(:summarizer_enabled).and_return(true)
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Usage: /summarizer <on|off>", type: :command)
        expect(application).to receive(:output_line).with("Current: summarizer=on", type: :command)
        command.execute("/summarizer")
      end

      it "returns :continue" do
        allow(application).to receive(:summarizer_enabled).and_return(false)
        expect(command.execute("/summarizer")).to eq(:continue)
      end
    end

    context "when turning summarizer on" do
      it "enables summarizer mode" do
        expect(application).to receive(:summarizer_enabled=).with(true)
        expect(history).to receive(:set_config).with("summarizer_enabled", "true")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("summarizer=on", type: :command)
        expect(application).to receive(:output_line).with("Summarizer will start on next /reset", type: :command)
        command.execute("/summarizer on")
      end

      it "returns :continue" do
        expect(command.execute("/summarizer on")).to eq(:continue)
      end
    end

    context "when turning summarizer off" do
      it "disables summarizer mode" do
        expect(application).to receive(:summarizer_enabled=).with(false)
        expect(history).to receive(:set_config).with("summarizer_enabled", "false")
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("summarizer=off", type: :command)
        command.execute("/summarizer off")
      end

      it "returns :continue" do
        expect(command.execute("/summarizer off")).to eq(:continue)
      end
    end

    context "when invalid argument provided" do
      it "displays error message" do
        expect(console).to receive(:puts).with("")
        expect(application).to receive(:output_line).with("Invalid option. Use: /summarizer <on|off>", type: :command)
        command.execute("/summarizer invalid")
      end

      it "returns :continue" do
        expect(command.execute("/summarizer invalid")).to eq(:continue)
      end
    end
  end
end
