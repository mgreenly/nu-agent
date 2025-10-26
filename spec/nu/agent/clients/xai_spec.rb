# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Clients::XAI do
  let(:api_key) { "test_api_key_123" }
  let(:client) { described_class.new(api_key: api_key) }
  let(:mock_openai_client) { instance_double(OpenAI::Client) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(mock_openai_client)
  end

  describe "#initialize" do
    it "creates an OpenAI client with X.AI endpoint" do
      expect(OpenAI::Client).to receive(:new).with(
        access_token: api_key,
        uri_base: "https://api.x.ai/v1"
      )
      described_class.new(api_key: api_key)
    end

    it "uses grok-3 as default model" do
      allow(OpenAI::Client).to receive(:new).and_return(mock_openai_client)
      client = described_class.new(api_key: api_key)
      expect(client.model).to eq("grok-3")
    end

    context "when no API key is provided" do
      it "loads from the XAI_API_KEY secrets file" do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return("file_api_key")

        expect(OpenAI::Client).to receive(:new).with(
          access_token: "file_api_key",
          uri_base: "https://api.x.ai/v1"
        )
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

    let(:xai_response) do
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
      allow(mock_openai_client).to receive(:chat).and_return(xai_response)
    end

    it "sends formatted messages to the X.AI API" do
      expect(mock_openai_client).to receive(:chat).with(
        parameters: hash_including(
          model: "grok-3",
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
        "model" => "grok-3",
        "tokens" => {
          "input" => 18,
          "output" => 10
        },
        "finish_reason" => "stop"
      )
    end

    it "allows custom system prompt" do
      custom_prompt = "You are a pirate."

      expect(mock_openai_client).to receive(:chat) do |args|
        messages = args[:parameters][:messages]
        expect(messages.first[:role]).to eq("system")
        expect(messages.first[:content]).to eq(custom_prompt)
      end.and_return(xai_response)

      client.send_message(messages: messages, system_prompt: custom_prompt)
    end
  end

  describe "#name" do
    it 'returns "X.AI"' do
      expect(client.name).to eq("X.AI")
    end
  end

  describe "#model" do
    it "returns the model identifier" do
      expect(client.model).to eq("grok-3")
    end
  end

  describe "#max_context" do
    it "returns the max context window for grok-3" do
      expect(client.max_context).to eq(1_000_000)
    end

    it "returns the max context window for grok-code-fast-1" do
      client = described_class.new(api_key: api_key, model: "grok-code-fast-1")
      expect(client.max_context).to eq(256_000)
    end
  end

  describe "#calculate_cost" do
    it "calculates cost for grok-3" do
      cost = client.calculate_cost(input_tokens: 1_000_000, output_tokens: 1_000_000)
      # $3.00 per million input + $15.00 per million output = $18.00
      expect(cost).to eq(18.0)
    end

    it "calculates cost for grok-code-fast-1" do
      client = described_class.new(api_key: api_key, model: "grok-code-fast-1")
      cost = client.calculate_cost(input_tokens: 1_000_000, output_tokens: 1_000_000)
      # $0.20 per million input + $1.50 per million output = $1.70
      expect(cost).to eq(1.7)
    end

    it "returns 0.0 for nil tokens" do
      cost = client.calculate_cost(input_tokens: nil, output_tokens: nil)
      expect(cost).to eq(0.0)
    end
  end

  describe "#list_models" do
    it "returns a curated list of X.AI models" do
      models = client.list_models
      expect(models[:provider]).to eq("X.AI")
      expect(models[:models]).to include(
        hash_including(id: "grok-3"),
        hash_including(id: "grok-code-fast-1")
      )
    end
  end
end
