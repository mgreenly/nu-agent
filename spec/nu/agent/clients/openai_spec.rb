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
        allow(File).to receive_messages(exist?: true, read: "file_api_key")

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

    it "formats tool result messages" do
      messages = [{
        "actor" => "orchestrator",
        "role" => "tool",
        "tool_call_id" => "call_123",
        "tool_result" => {
          "name" => "file_read",
          "result" => { "content" => "file contents" }
        }
      }]

      formatted = client.send(:format_messages, messages, system_prompt: nil)

      expect(formatted).to eq([{
                                role: "tool",
                                tool_call_id: "call_123",
                                content: '{"content":"file contents"}'
                              }])
    end

    it "formats tool call messages" do
      messages = [{
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "Using a tool",
        "tool_calls" => [{
          "id" => "call_123",
          "name" => "file_read",
          "arguments" => { "path" => "/test.txt" }
        }]
      }]

      formatted = client.send(:format_messages, messages, system_prompt: nil)

      expect(formatted).to eq([{
                                role: "assistant",
                                content: "Using a tool",
                                tool_calls: [{
                                  id: "call_123",
                                  type: "function",
                                  function: {
                                    name: "file_read",
                                    arguments: '{"path":"/test.txt"}'
                                  }
                                }]
                              }])
    end

    it "formats tool call messages without content" do
      messages = [{
        "actor" => "orchestrator",
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [{
          "id" => "call_456",
          "name" => "test_tool",
          "arguments" => {}
        }]
      }]

      formatted = client.send(:format_messages, messages, system_prompt: nil)

      expect(formatted.first).not_to have_key(:content)
      expect(formatted.first[:tool_calls]).not_to be_nil
    end
  end

  describe "#initialize with custom model" do
    it "accepts a custom model" do
      custom_client = described_class.new(api_key: api_key, model: "gpt-5-mini")
      expect(custom_client.model).to eq("gpt-5-mini")
    end
  end

  describe "#send_message with tools" do
    let(:tools) { [{ "name" => "file_read", "parameters" => {} }] }
    let(:openai_response) do
      {
        "choices" => [{
          "message" => {
            "content" => nil,
            "tool_calls" => [{
              "id" => "call_123",
              "function" => {
                "name" => "file_read",
                "arguments" => '{"path":"/test.txt"}'
              }
            }]
          },
          "finish_reason" => "tool_calls"
        }],
        "usage" => {
          "prompt_tokens" => 50,
          "completion_tokens" => 20
        }
      }
    end

    it "includes tools in request when provided" do
      allow(mock_openai_client).to receive(:chat).and_return(openai_response)

      expect(mock_openai_client).to receive(:chat).with(
        parameters: hash_including(
          tools: tools
        )
      )

      client.send_message(messages: [], tools: tools)
    end

    it "extracts tool calls from response" do
      allow(mock_openai_client).to receive(:chat).and_return(openai_response)

      response = client.send_message(messages: [], tools: tools)

      expect(response["tool_calls"]).to eq([{
                                             "id" => "call_123",
                                             "name" => "file_read",
                                             "arguments" => { "path" => "/test.txt" }
                                           }])
    end

    it "does not include tools when nil" do
      allow(mock_openai_client).to receive(:chat).and_return(openai_response)

      expect(mock_openai_client).to receive(:chat).with(
        parameters: hash_not_including(:tools)
      )

      client.send_message(messages: [], tools: nil)
    end

    it "does not include tools when empty" do
      allow(mock_openai_client).to receive(:chat).and_return(openai_response)

      expect(mock_openai_client).to receive(:chat).with(
        parameters: hash_not_including(:tools)
      )

      client.send_message(messages: [], tools: [])
    end
  end

  describe "#send_message error handling" do
    it "handles Faraday errors" do
      error = Faraday::Error.new("Connection failed")
      allow(error).to receive_messages(response: nil, response_body: nil, message: "Connection failed")
      allow(mock_openai_client).to receive(:chat).and_raise(error)

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
      allow(mock_openai_client).to receive(:chat).and_raise(error)

      response = client.send_message(messages: [])

      expect(response["error"]["status"]).to eq(401)
      expect(response["error"]["headers"]).to eq({ "content-type" => "application/json" })
      expect(response["error"]["body"]).to include("Invalid API key")
    end
  end

  describe "#generate_embedding" do
    let(:embedding_vector) { Array.new(1536) { rand } }
    let(:embedding_response) do
      {
        "data" => [{ "embedding" => embedding_vector }],
        "usage" => { "total_tokens" => 10 },
        "model" => "text-embedding-3-small"
      }
    end

    before do
      allow(mock_openai_client).to receive(:embeddings).and_return(embedding_response)
    end

    it "generates embedding for single text" do
      result = client.generate_embedding("Hello world")

      expect(result["embeddings"]).to eq(embedding_vector)
      expect(result["model"]).to eq("text-embedding-3-small")
      expect(result["tokens"]).to eq(10)
    end

    it "generates embeddings for array of texts" do
      embedding_vector2 = Array.new(1536) { rand }
      multi_response = {
        "data" => [
          { "embedding" => embedding_vector },
          { "embedding" => embedding_vector2 }
        ],
        "usage" => { "total_tokens" => 20 },
        "model" => "text-embedding-3-small"
      }
      allow(mock_openai_client).to receive(:embeddings).and_return(multi_response)

      result = client.generate_embedding(["Text 1", "Text 2"])

      expect(result["embeddings"]).to be_an(Array)
      expect(result["embeddings"].length).to eq(2)
    end

    it "calculates cost correctly" do
      result = client.generate_embedding("Test")

      expected_cost = (10 / 1_000_000.0) * 0.020
      expect(result["spend"]).to eq(expected_cost)
    end

    it "handles missing usage information" do
      response_no_usage = {
        "data" => [{ "embedding" => embedding_vector }],
        "model" => "text-embedding-3-small"
      }
      allow(mock_openai_client).to receive(:embeddings).and_return(response_no_usage)

      result = client.generate_embedding("Test")

      expect(result["tokens"]).to eq(0)
      expect(result["spend"]).to eq(0.0)
    end

    it "handles Faraday errors" do
      error = Faraday::Error.new("API Error")
      allow(error).to receive_messages(response: nil, response_body: nil, message: "API Error")
      allow(mock_openai_client).to receive(:embeddings).and_raise(error)

      result = client.generate_embedding("Test")

      expect(result).to have_key("error")
    end
  end

  describe "#max_context" do
    it "returns max context for the model" do
      expect(client.max_context).to eq(400_000)
    end

    it "returns default max context for unknown model" do
      unknown_client = described_class.new(api_key: api_key, model: "unknown-model")
      expect(unknown_client.max_context).to eq(400_000)
    end
  end

  describe "#format_tools" do
    it "delegates to tool_registry" do
      tool_registry = instance_double("ToolRegistry")
      expect(tool_registry).to receive(:for_openai).and_return([])

      client.format_tools(tool_registry)
    end
  end

  describe "#list_models" do
    it "returns list of available models" do
      result = client.list_models

      expect(result[:provider]).to eq("OpenAI")
      expect(result[:models]).to be_an(Array)
      expect(result[:models].length).to eq(3)
      expect(result[:models].first).to have_key(:id)
      expect(result[:models].first).to have_key(:display_name)
    end
  end

  describe "#calculate_cost" do
    it "calculates cost for input and output tokens" do
      cost = client.calculate_cost(input_tokens: 1_000_000, output_tokens: 1_000_000)

      # gpt-5: $1.25 per 1M input, $10.00 per 1M output
      expect(cost).to eq(11.25)
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

      # Should use gpt-5 default pricing
      expect(cost).to eq(11.25)
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

  describe "response extraction edge cases" do
    it "handles response with nil tool_calls" do
      response_no_tools = {
        "choices" => [{
          "message" => {
            "content" => "Response",
            "tool_calls" => nil
          },
          "finish_reason" => "stop"
        }],
        "usage" => {
          "prompt_tokens" => 10,
          "completion_tokens" => 5
        }
      }

      allow(mock_openai_client).to receive(:chat).and_return(response_no_tools)

      result = client.send_message(messages: [])

      expect(result["tool_calls"]).to be_nil
    end

    it "handles response with empty tool_calls array" do
      response_empty_tools = {
        "choices" => [{
          "message" => {
            "content" => "Response",
            "tool_calls" => []
          },
          "finish_reason" => "stop"
        }],
        "usage" => {
          "prompt_tokens" => 10,
          "completion_tokens" => 5
        }
      }

      allow(mock_openai_client).to receive(:chat).and_return(response_empty_tools)

      result = client.send_message(messages: [])

      expect(result["tool_calls"]).to be_nil
    end
  end
end
