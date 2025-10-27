# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::SessionStatistics do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:orchestrator) { instance_double("Orchestrator", max_context: 200_000) }
  let(:console) { instance_double(Nu::Agent::ConsoleIO, puts: nil) }
  let(:conversation_id) { 1 }
  let(:session_start_time) { Time.now - 60 }

  let(:statistics) do
    described_class.new(
      history: history,
      orchestrator: orchestrator,
      console: console,
      conversation_id: conversation_id,
      session_start_time: session_start_time
    )
  end

  describe "#should_display?" do
    it "returns true when message has tokens_input, tokens_output, and no tool_calls" do
      message = {
        "tokens_input" => 10,
        "tokens_output" => 5,
        "tool_calls" => nil
      }

      expect(statistics.should_display?(message)).to be true
    end

    it "returns false when message has tool_calls" do
      message = {
        "tokens_input" => 10,
        "tokens_output" => 5,
        "tool_calls" => [{ "name" => "some_tool" }]
      }

      expect(statistics.should_display?(message)).to be false
    end

    it "returns false when message lacks tokens_input" do
      message = {
        "tokens_input" => nil,
        "tokens_output" => 5
      }

      expect(statistics.should_display?(message)).to be false
    end

    it "returns false when message lacks tokens_output" do
      message = {
        "tokens_input" => 10,
        "tokens_output" => nil
      }

      expect(statistics.should_display?(message)).to be false
    end
  end

  describe "#display" do
    let(:tokens_data) do
      {
        "input" => 100,
        "output" => 50,
        "total" => 150,
        "spend" => 0.001500
      }
    end

    before do
      allow(history).to receive(:session_tokens).and_return(tokens_data)
    end

    context "when debug is false" do
      it "does not display any statistics" do
        expect(console).not_to receive(:puts)

        statistics.display(exchange_start_time: Time.now - 2, debug: false)
      end
    end

    context "when debug is true" do
      it "displays token statistics with percentage of max context" do
        # 150 / 200_000 = 0.075%
        expected_output = "\e[90mSession tokens: 100 in / 50 out / 150 Total / (0.1% of 200000)\e[0m"

        expect(console).to receive(:puts).with("").ordered
        expect(console).to receive(:puts).with(expected_output).ordered

        statistics.display(exchange_start_time: nil, debug: true)
      end

      it "displays spend statistics" do
        expected_output = "\e[90mSession spend: $0.001500\e[0m"

        expect(console).to receive(:puts).with("").ordered
        expect(console).to receive(:puts).with(anything).ordered # token stats
        expect(console).to receive(:puts).with(expected_output).ordered

        statistics.display(exchange_start_time: nil, debug: true)
      end

      it "displays elapsed time when exchange_start_time is provided" do
        start_time = Time.now - 2.5
        expected_output = "\e[90mElapsed time: 2.50s\e[0m"

        expect(console).to receive(:puts).with("").ordered
        expect(console).to receive(:puts).with(anything).ordered # token stats
        expect(console).to receive(:puts).with(anything).ordered # spend stats
        expect(console).to receive(:puts).with(expected_output).ordered

        statistics.display(exchange_start_time: start_time, debug: true)
      end

      it "does not display elapsed time when exchange_start_time is nil" do
        expect(console).to receive(:puts).with("").ordered
        expect(console).to receive(:puts).with(anything).ordered # token stats
        expect(console).to receive(:puts).with(anything).ordered # spend stats
        expect(console).not_to receive(:puts).with(/Elapsed time/)

        statistics.display(exchange_start_time: nil, debug: true)
      end

      it "queries history with correct conversation_id and session_start_time" do
        expect(history).to receive(:session_tokens).with(
          conversation_id: conversation_id,
          since: session_start_time
        ).and_return(tokens_data)

        statistics.display(exchange_start_time: nil, debug: true)
      end
    end
  end
end
