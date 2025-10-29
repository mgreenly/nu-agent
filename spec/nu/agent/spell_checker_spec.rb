# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::SpellChecker do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:conversation_id) { 123 }
  let(:client) { instance_double(Nu::Agent::Clients::Anthropic) }
  let(:spell_checker) { described_class.new(history: history, conversation_id: conversation_id, client: client) }

  describe "#initialize" do
    it "sets history, conversation_id, and client" do
      expect(spell_checker.instance_variable_get(:@history)).to eq(history)
      expect(spell_checker.instance_variable_get(:@conversation_id)).to eq(conversation_id)
      expect(spell_checker.instance_variable_get(:@client)).to eq(client)
    end
  end

  describe "#check_spelling" do
    let(:original_text) { "This is a tset message with mispellings" }
    let(:corrected_text) { "This is a test message with misspellings" }
    let(:spell_check_messages) do
      [
        { "actor" => "spell_checker", "role" => "user", "content" => "Fix ONLY misspelled words..." }
      ]
    end
    let(:client_response) do
      {
        "content" => "  #{corrected_text}  ",
        "model" => "claude-3-5-sonnet-20241022",
        "tokens" => { "input" => 10, "output" => 5 },
        "spend" => 0.001
      }
    end

    before do
      allow(history).to receive(:add_message)
      allow(history).to receive(:messages).and_return(spell_check_messages)
      allow(client).to receive(:send_message).and_return(client_response)
    end

    it "adds spell check request to history" do
      expect(history).to receive(:add_message).with(
        conversation_id: conversation_id,
        actor: "spell_checker",
        role: "user",
        content: a_string_including(original_text),
        redacted: true
      )

      spell_checker.check_spelling(original_text)
    end

    it "retrieves spell check messages from history" do
      expect(history).to receive(:messages).with(
        conversation_id: conversation_id,
        include_in_context_only: true
      )

      spell_checker.check_spelling(original_text)
    end

    it "sends messages to client with system prompt" do
      expect(client).to receive(:send_message).with(
        messages: spell_check_messages,
        system_prompt: a_string_including("spell checker")
      )

      spell_checker.check_spelling(original_text)
    end

    it "saves corrected response to history" do
      expect(history).to receive(:add_message).with(
        conversation_id: conversation_id,
        actor: "spell_checker",
        role: "assistant",
        content: corrected_text,
        model: "claude-3-5-sonnet-20241022",
        tokens_input: 10,
        tokens_output: 5,
        spend: 0.001,
        redacted: true
      )

      spell_checker.check_spelling(original_text)
    end

    it "returns corrected text stripped of whitespace" do
      result = spell_checker.check_spelling(original_text)

      expect(result).to eq(corrected_text)
    end

    context "when an error occurs" do
      before do
        allow(client).to receive(:send_message).and_raise(StandardError.new("API error"))
      end

      it "returns original text unchanged" do
        result = spell_checker.check_spelling(original_text)

        expect(result).to eq(original_text)
      end

      it "does not raise the error" do
        expect { spell_checker.check_spelling(original_text) }.not_to raise_error
      end
    end
  end

  describe "private methods" do
    describe "#spell_check_messages_from_history" do
      let(:all_messages) do
        [
          { "actor" => "spell_checker", "role" => "user", "content" => "Message 1" },
          { "actor" => "user", "role" => "user", "content" => "User message" },
          { "actor" => "spell_checker", "role" => "assistant", "content" => "Message 2" },
          { "actor" => "orchestrator", "role" => "assistant", "content" => "Orchestrator message" }
        ]
      end

      before do
        allow(history).to receive(:messages).and_return(all_messages)
      end

      it "filters messages to only include spell_checker actor" do
        result = spell_checker.send(:spell_check_messages_from_history)

        expect(result.length).to eq(2)
        expect(result[0]["actor"]).to eq("spell_checker")
        expect(result[0]["content"]).to eq("Message 1")
        expect(result[1]["actor"]).to eq("spell_checker")
        expect(result[1]["content"]).to eq("Message 2")
      end
    end
  end
end
