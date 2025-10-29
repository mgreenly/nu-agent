# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/verbosity_command"

RSpec.describe Nu::Agent::Commands::VerbosityCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(history: history, console: console)
    allow(application).to receive(:verbosity=)
    allow(history).to receive(:set_config)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    context "when no argument provided" do
      it "displays usage message" do
        allow(application).to receive(:verbosity).and_return(0)
        expect(console).to receive(:puts).with("\e[90mUsage: /verbosity <number>\e[0m")
        expect(console).to receive(:puts).with("\e[90mCurrent: verbosity=0\e[0m")
        command.execute("/verbosity")
      end

      it "returns :continue" do
        allow(application).to receive(:verbosity).and_return(0)
        expect(command.execute("/verbosity")).to eq(:continue)
      end
    end

    context "when setting a valid number" do
      it "sets verbosity level" do
        expect(application).to receive(:verbosity=).with(3)
        allow(application).to receive(:verbosity).and_return(3)
        expect(history).to receive(:set_config).with("verbosity", "3")
        expect(console).to receive(:puts).with("\e[90mverbosity=3\e[0m")
        command.execute("/verbosity 3")
      end

      it "returns :continue" do
        allow(application).to receive(:verbosity).and_return(3)
        expect(command.execute("/verbosity 3")).to eq(:continue)
      end
    end

    context "when invalid argument provided" do
      it "displays error message for non-numeric input" do
        expect(console).to receive(:puts).with("\e[90mInvalid option. Use: /verbosity <number>\e[0m")
        command.execute("/verbosity abc")
      end

      it "returns :continue" do
        expect(command.execute("/verbosity abc")).to eq(:continue)
      end
    end
  end
end
