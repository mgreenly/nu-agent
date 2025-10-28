# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/reset_command"

RSpec.describe Nu::Agent::Commands::ResetCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:formatter) { instance_double("Nu::Agent::Formatter") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive(:history).and_return(history)
    allow(application).to receive(:formatter).and_return(formatter)
    allow(application).to receive(:console).and_return(console)
    allow(application).to receive(:conversation_id=)
    allow(application).to receive(:conversation_id).and_return(123)
    allow(application).to receive(:session_start_time=)
    allow(application).to receive(:output_line)
    allow(application).to receive(:start_summarization_worker)
    allow(application).to receive(:clear_screen)
    allow(history).to receive(:create_conversation).and_return(123)
    allow(formatter).to receive(:reset_session)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    it "clears screen via clear_screen method" do
      expect(application).to receive(:clear_screen)
      command.execute("/reset")
    end

    it "creates a new conversation" do
      expect(history).to receive(:create_conversation).and_return(123)
      expect(application).to receive(:conversation_id=).with(123)
      command.execute("/reset")
    end

    it "resets the formatter session" do
      expect(formatter).to receive(:reset_session).with(conversation_id: 123)
      command.execute("/reset")
    end

    it "starts summarization worker" do
      expect(application).to receive(:start_summarization_worker)
      command.execute("/reset")
    end

    it "outputs confirmation message" do
      expect(console).to receive(:puts).with("")
      expect(application).to receive(:output_line).with("Conversation reset", type: :debug)
      command.execute("/reset")
    end

    it "returns :continue" do
      expect(command.execute("/reset")).to eq(:continue)
    end
  end
end
