# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Clients::Anthropic do
  let(:api_key) { "test_api_key_123" }
  let(:client) { described_class.new(api_key: api_key) }
  let(:mock_anthropic_client) { instance_double(Anthropic::Client) }

  before do
    allow(Anthropic::Client).to receive(:new).and_return(mock_anthropic_client)
  end

  describe "#initialize" do
    it "creates an Anthropic client with the provided API key" do
      expect(Anthropic::Client).to receive(:new).with(access_token: api_key)
      described_class.new(api_key: api_key)
    end

    context "when no API key is provided" do
      it "loads from the secrets file" do
        allow(File).to receive_messages(exist?: true, read: "file_api_key")

        expect(Anthropic::Client).to receive(:new).with(access_token: "file_api_key")
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

    let(:anthropic_response) do
      {
        "content" => [{ "type" => "text", "text" => "Hello! How can I help you?" }],
        "usage" => {
          "input_tokens" => 15,
          "output_tokens" => 10
        },
        "stop_reason" => "end_turn"
      }
    end

    before do
      allow(mock_anthropic_client).to receive(:messages).and_return(anthropic_response)
    end

    it "sends formatted messages to the Anthropic API" do
      expect(mock_anthropic_client).to receive(:messages).with(
        parameters: hash_including(
          model: "claude-sonnet-4-5",
          messages: [
            { role: "user", content: "Hello" },
            { role: "assistant", content: "Hi there!" }
          ]
        )
      )

      client.send_message(messages: messages)
    end

    it "returns a normalized response" do
      response = client.send_message(messages: messages)

      expect(response).to include(
        "content" => "Hello! How can I help you?",
        "model" => "claude-sonnet-4-5",
        "tokens" => {
          "input" => 15,
          "output" => 10
        },
        "finish_reason" => "end_turn"
      )
    end

    it "includes the system prompt" do
      expect(mock_anthropic_client).to receive(:messages).with(
        parameters: hash_including(
          system: a_string_including("raw text, do not use markdown")
        )
      )

      client.send_message(messages: messages)
    end

    it "allows custom system prompt" do
      custom_prompt = "You are a pirate."

      expect(mock_anthropic_client).to receive(:messages).with(
        parameters: hash_including(
          system: custom_prompt
        )
      )

      client.send_message(messages: messages, system_prompt: custom_prompt)
    end
  end

  describe "#name" do
    it 'returns "Anthropic"' do
      expect(client.name).to eq("Anthropic")
    end
  end

  describe "#model" do
    it "returns the model identifier" do
      expect(client.model).to eq("claude-sonnet-4-5")
    end
  end

  describe "#format_messages" do
    it "converts internal message format to Anthropic format" do
      messages = [
        { "actor" => "user", "role" => "user", "content" => "Hello" },
        { "actor" => "orchestrator", "role" => "assistant", "content" => "Hi!" }
      ]

      formatted = client.send(:format_messages, messages)

      expect(formatted).to eq([
                                { role: "user", content: "Hello" },
                                { role: "assistant", content: "Hi!" }
                              ])
    end

    it "strips out actor information" do
      messages = [
        { "actor" => "orchestrator", "role" => "assistant", "content" => "Response" }
      ]

      formatted = client.send(:format_messages, messages)

      expect(formatted.first).not_to have_key(:actor)
    end

    it "formats tool result messages" do
      messages = [{
        "actor" => "orchestrator",
        "role" => "tool",
        "tool_call_id" => "toolu_123",
        "tool_result" => {
          "name" => "file_read",
          "result" => { "content" => "file contents" }
        }
      }]

      formatted = client.send(:format_messages, messages)

      expect(formatted).to eq([{
                                role: "user",
                                content: [{
                                  type: "tool_result",
                                  tool_use_id: "toolu_123",
                                  content: "{\"content\":\"file contents\"}"
                                }]
                              }])
    end

    it "formats tool call messages with content" do
      messages = [{
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "Using a tool",
        "tool_calls" => [{
          "id" => "toolu_123",
          "name" => "file_read",
          "arguments" => { "path" => "/test.txt" }
        }]
      }]

      formatted = client.send(:format_messages, messages)

      expect(formatted).to eq([{
                                role: "assistant",
                                content: [
                                  { type: "text", text: "Using a tool" },
                                  {
                                    type: "tool_use",
                                    id: "toolu_123",
                                    name: "file_read",
                                    input: { "path" => "/test.txt" }
                                  }
                                ]
                              }])
    end

    it "formats tool call messages without content" do
      messages = [{
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [{
          "id" => "toolu_456",
          "name" => "test_tool",
          "arguments" => {}
        }]
      }]

      formatted = client.send(:format_messages, messages)

      expect(formatted.first[:content]).to eq([{
                                                type: "tool_use",
                                                id: "toolu_456",
                                                name: "test_tool",
                                                input: {}
                                              }])
    end
  end

  describe "#send_message with tools" do
    let(:tools) { [{ "name" => "file_read", "parameters" => {} }] }
    let(:anthropic_response) do
      {
        "content" => [
          {
            "type" => "tool_use",
            "id" => "toolu_123",
            "name" => "file_read",
            "input" => { "path" => "/test.txt" }
          }
        ],
        "usage" => {
          "input_tokens" => 50,
          "output_tokens" => 20
        },
        "stop_reason" => "tool_use"
      }
    end

    it "includes tools in request when provided" do
      allow(mock_anthropic_client).to receive(:messages).and_return(anthropic_response)

      expect(mock_anthropic_client).to receive(:messages).with(
        parameters: hash_including(
          tools: tools
        )
      )

      client.send_message(messages: [], tools: tools)
    end

    it "extracts tool calls from response" do
      allow(mock_anthropic_client).to receive(:messages).and_return(anthropic_response)

      response = client.send_message(messages: [], tools: tools)

      expect(response["tool_calls"]).to eq([{
                                             "id" => "toolu_123",
                                             "name" => "file_read",
                                             "arguments" => { "path" => "/test.txt" }
                                           }])
    end

    it "does not include tools when nil" do
      allow(mock_anthropic_client).to receive(:messages).and_return(anthropic_response)

      expect(mock_anthropic_client).to receive(:messages).with(
        parameters: hash_not_including(:tools)
      )

      client.send_message(messages: [], tools: nil)
    end

    it "does not include tools when empty" do
      allow(mock_anthropic_client).to receive(:messages).and_return(anthropic_response)

      expect(mock_anthropic_client).to receive(:messages).with(
        parameters: hash_not_including(:tools)
      )

      client.send_message(messages: [], tools: [])
    end
  end

  describe "#send_message error handling" do
    it "handles Faraday errors" do
      error = Faraday::Error.new("Connection failed")
      allow(error).to receive_messages(response: nil, response_body: nil, message: "Connection failed")
      allow(mock_anthropic_client).to receive(:messages).and_raise(error)

      response = client.send_message(messages: [])

      expect(response).to have_key("error")
      expect(response["error"]["status"]).to eq("unknown")
      expect(response["content"]).to include("API Error")
    end

    it "extracts error details from response" do
      error_response = {
        status: 401,
        headers: { "content-type" => "application/json" },
        body: '{"error": "Invalid API key"}'
      }
      error = Faraday::UnauthorizedError.new("Unauthorized")
      allow(error).to receive(:response).and_return(error_response)
      allow(mock_anthropic_client).to receive(:messages).and_raise(error)

      response = client.send_message(messages: [])

      expect(response["error"]["status"]).to eq(401)
      expect(response["error"]["headers"]).to eq({ "content-type" => "application/json" })
      expect(response["error"]["body"]).to include("Invalid API key")
    end
  end

  describe "#initialize with custom model" do
    it "accepts a custom model" do
      custom_client = described_class.new(api_key: api_key, model: "claude-haiku-4-5")
      expect(custom_client.model).to eq("claude-haiku-4-5")
    end
  end

  describe "#max_context" do
    it "returns max context for the model" do
      expect(client.max_context).to eq(200_000)
    end

    it "returns default max context for unknown model" do
      unknown_client = described_class.new(api_key: api_key, model: "unknown-model")
      expect(unknown_client.max_context).to eq(200_000)
    end
  end

  describe "#format_tools" do
    it "delegates to tool_registry" do
      tool_registry = instance_double("ToolRegistry")
      expect(tool_registry).to receive(:for_anthropic).and_return([])

      client.format_tools(tool_registry)
    end
  end

  describe "#list_models" do
    it "returns list of available models" do
      result = client.list_models

      expect(result[:provider]).to eq("Anthropic")
      expect(result[:models]).to be_an(Array)
      expect(result[:models].length).to eq(3)
      expect(result[:models].first).to have_key(:id)
      expect(result[:models].first).to have_key(:display_name)
    end
  end

  describe "#calculate_cost" do
    it "calculates cost for input and output tokens" do
      cost = client.calculate_cost(input_tokens: 1_000_000, output_tokens: 1_000_000)

      # claude-sonnet-4-5: $3.00 per 1M input, $15.00 per 1M output
      expect(cost).to eq(18.0)
    end

    it "returns 0 when tokens are nil" do
      cost = client.calculate_cost(input_tokens: nil, output_tokens: 100)
      expect(cost).to eq(0.0)

      cost = client.calculate_cost(input_tokens: 100, output_tokens: nil)
      expect(cost).to eq(0.0)
    end

    it "handles unknown model by using default pricing" do
      unknown_client = described_class.new(api_key: api_key, model: "unknown-model")
      cost = unknown_client.calculate_cost(input_tokens: 1_000_000, output_tokens: 1_000_000)

      # Should use claude-sonnet-4-5 default pricing
      expect(cost).to eq(18.0)
    end
  end

  describe "#load_api_key error handling" do
    it "raises error when file read fails" do
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_raise(StandardError.new("Permission denied"))

      expect do
        described_class.new
      end.to raise_error(Nu::Agent::Error, /Error loading API key: Permission denied/)
    end
  end
end
