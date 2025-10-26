# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Clients::OpenAI do
  let(:api_key) { "test_api_key_123" }
  let(:client) { described_class.new(api_key: api_key) }
  let(:mock_openai_client) { instance_double(OpenAI::Client) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(mock_openai_client)
  end

  describe "#initialize" do
    it "creates an OpenAI client with the provided API key" do
      expect(OpenAI::Client).to receive(:new).with(access_token: api_key)
      described_class.new(api_key: api_key)
    end

    context "when no API key is provided" do
      it "loads from the secrets file" do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return("file_api_key")

        expect(OpenAI::Client).to receive(:new).with(access_token: "file_api_key")
        described_class.new
      end

      it "raises an error if the secrets file does not exist" do
        allow(File).to receive(:exist?).and_return(false)

        expect do
          described_class.new
        end.to raise_error(Nu::Agent::Error, /API key not found/)
      end
    end
  end

  describe "#send_message" do
    let(:messages) do
      [
        { "actor" => "user", "role" => "user", "content" => "Hello" },
        { "actor" => "orchestrator", "role" => "assistant", "content" => "Hi there!" }
      ]
    end

    let(:openai_response) do
      {
        "choices" => [{
          "message" => {
            "content" => "Hello! How can I help you?"
          },
          "finish_reason" => "stop"
        }],
        "usage" => {
          "prompt_tokens" => 18,
          "completion_tokens" => 10
        }
      }
    end

    before do
      allow(mock_openai_client).to receive(:chat).and_return(openai_response)
    end

    it "sends formatted messages to the OpenAI API" do
      expect(mock_openai_client).to receive(:chat).with(
        parameters: hash_including(
          model: "gpt-5",
          messages: array_including(
            { role: "system", content: a_string_including("raw text, do not use markdown") },
            { role: "user", content: "Hello" },
            { role: "assistant", content: "Hi there!" }
          )
        )
      )

      client.send_message(messages: messages)
    end

    it "returns a normalized response" do
      response = client.send_message(messages: messages)

      expect(response).to include(
        "content" => "Hello! How can I help you?",
        "model" => "gpt-5",
        "tokens" => {
          "input" => 18,
          "output" => 10
        },
        "finish_reason" => "stop"
      )
    end

    it "prepends system prompt as first message" do
      expect(mock_openai_client).to receive(:chat) do |args|
        messages = args[:parameters][:messages]
        expect(messages.first[:role]).to eq("system")
        expect(messages.first[:content]).to include("raw text, do not use markdown")
      end.and_return(openai_response)

      client.send_message(messages: messages)
    end

    it "allows custom system prompt" do
      custom_prompt = "You are a pirate."

      expect(mock_openai_client).to receive(:chat) do |args|
        messages = args[:parameters][:messages]
        expect(messages.first[:role]).to eq("system")
        expect(messages.first[:content]).to eq(custom_prompt)
      end.and_return(openai_response)

      client.send_message(messages: messages, system_prompt: custom_prompt)
    end
  end

  describe "#name" do
    it 'returns "OpenAI"' do
      expect(client.name).to eq("OpenAI")
    end
  end

  describe "#model" do
    it "returns the model identifier" do
      expect(client.model).to eq("gpt-5")
    end
  end

  describe "#format_messages" do
    it "converts internal message format to OpenAI format" do
      messages = [
        { "actor" => "user", "role" => "user", "content" => "Hello" },
        { "actor" => "orchestrator", "role" => "assistant", "content" => "Hi!" }
      ]

      formatted = client.send(:format_messages, messages, system_prompt: "System")

      expect(formatted).to eq([
                                { role: "system", content: "System" },
                                { role: "user", content: "Hello" },
                                { role: "assistant", content: "Hi!" }
                              ])
    end

    it "strips out actor information" do
      messages = [
        { "actor" => "orchestrator", "role" => "assistant", "content" => "Response" }
      ]

      formatted = client.send(:format_messages, messages, system_prompt: nil)

      expect(formatted.last).not_to have_key(:actor)
    end

    it "handles empty system prompt" do
      messages = [{ "actor" => "user", "role" => "user", "content" => "Hi" }]

      formatted = client.send(:format_messages, messages, system_prompt: "")

      expect(formatted).to eq([
                                { role: "user", content: "Hi" }
                              ])
    end

    it "handles nil system prompt" do
      messages = [{ "actor" => "user", "role" => "user", "content" => "Hi" }]

      formatted = client.send(:format_messages, messages, system_prompt: nil)

      expect(formatted).to eq([
                                { role: "user", content: "Hi" }
                              ])
    end
  end
end
