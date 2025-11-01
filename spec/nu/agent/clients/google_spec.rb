# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Clients::Google do
  let(:api_key) { "test_api_key_123" }
  let(:client) { described_class.new(api_key: api_key) }
  let(:mock_gemini_client) { double("Gemini") }

  before do
    allow(Gemini).to receive(:new).and_return(mock_gemini_client)
  end

  describe "#initialize" do
    it "creates a Gemini client with the provided API key" do
      expect(Gemini).to receive(:new).with(
        credentials: {
          service: "generative-language-api",
          api_key: api_key,
          version: "v1beta"
        },
        options: { model: "gemini-2.5-flash", server_sent_events: false }
      )
      described_class.new(api_key: api_key)
    end

    context "when no API key is provided" do
      it "loads from the secrets file" do
        allow(File).to receive_messages(exist?: true, read: "file_api_key")

        expect(Gemini).to receive(:new).with(
          credentials: hash_including(api_key: "file_api_key"),
          options: anything
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

    let(:gemini_response) do
      {
        "candidates" => [{
          "content" => {
            "parts" => [{ "text" => "Hello! How can I help you?" }]
          },
          "finishReason" => "STOP"
        }],
        "usageMetadata" => {
          "promptTokenCount" => 20,
          "candidatesTokenCount" => 12
        }
      }
    end

    before do
      allow(mock_gemini_client).to receive(:generate_content).and_return(gemini_response)
    end

    it "sends formatted messages to the Gemini API" do
      expect(mock_gemini_client).to receive(:generate_content) do |args|
        contents = args[:contents]
        expect(contents).to be_an(Array)
        expect(contents.length).to eq(3)
        expect(contents[0][:role]).to eq("user")
        expect(contents[0][:parts][0][:text]).to include("raw text, do not use markdown")
        expect(contents[1][:role]).to eq("user")
        expect(contents[2][:role]).to eq("model")
      end.and_return(gemini_response)

      client.send_message(messages: messages)
    end

    it "returns a normalized response" do
      response = client.send_message(messages: messages)

      expect(response).to include(
        "content" => "Hello! How can I help you?",
        "model" => "gemini-2.5-flash",
        "tokens" => {
          "input" => 20,
          "output" => 12
        },
        "finish_reason" => "STOP"
      )
    end

    it "converts assistant role to model role" do
      expect(mock_gemini_client).to receive(:generate_content) do |args|
        contents = args[:contents]
        model_message = contents.find { |m| m[:parts][0][:text] == "Hi there!" }
        expect(model_message[:role]).to eq("model")
      end.and_return(gemini_response)

      client.send_message(messages: messages)
    end

    it "prepends system prompt as first user message" do
      expect(mock_gemini_client).to receive(:generate_content) do |args|
        contents = args[:contents]
        expect(contents.first[:role]).to eq("user")
        expect(contents.first[:parts][0][:text]).to include("raw text, do not use markdown")
      end.and_return(gemini_response)

      client.send_message(messages: messages)
    end

    it "allows custom system prompt" do
      custom_prompt = "You are a pirate."

      expect(mock_gemini_client).to receive(:generate_content) do |args|
        contents = args[:contents]
        expect(contents.first[:parts][0][:text]).to eq(custom_prompt)
      end.and_return(gemini_response)

      client.send_message(messages: messages, system_prompt: custom_prompt)
    end

    it "replaces {{DATE}} placeholder with current date" do
      prompt_with_date = "Today is {{DATE}}. You are a helpful assistant."
      current_date = Time.now.strftime("%Y-%m-%d")
      expected_prompt = "Today is #{current_date}. You are a helpful assistant."

      expect(mock_gemini_client).to receive(:generate_content) do |args|
        contents = args[:contents]
        expect(contents.first[:parts][0][:text]).to eq(expected_prompt)
      end.and_return(gemini_response)

      client.send_message(messages: messages, system_prompt: prompt_with_date)
    end
  end

  describe "#name" do
    it 'returns "Google"' do
      expect(client.name).to eq("Google")
    end
  end

  describe "#model" do
    it "returns the model identifier" do
      expect(client.model).to eq("gemini-2.5-flash")
    end
  end

  describe "#format_messages" do
    it "converts internal message format to Gemini format" do
      messages = [
        { "actor" => "user", "role" => "user", "content" => "Hello" },
        { "actor" => "orchestrator", "role" => "assistant", "content" => "Hi!" }
      ]

      formatted = client.send(:format_messages, messages, system_prompt: "System")

      expect(formatted).to eq([
                                { role: "user", parts: [{ text: "System" }] },
                                { role: "user", parts: [{ text: "Hello" }] },
                                { role: "model", parts: [{ text: "Hi!" }] }
                              ])
    end

    it "converts assistant role to model role" do
      messages = [
        { "actor" => "orchestrator", "role" => "assistant", "content" => "Response" }
      ]

      formatted = client.send(:format_messages, messages, system_prompt: nil)

      expect(formatted.first[:role]).to eq("model")
    end

    it "strips out actor information" do
      messages = [
        { "actor" => "orchestrator", "role" => "assistant", "content" => "Response" }
      ]

      formatted = client.send(:format_messages, messages, system_prompt: nil)

      expect(formatted.first).not_to have_key(:actor)
    end

    it "handles empty system prompt" do
      messages = [{ "actor" => "user", "role" => "user", "content" => "Hi" }]

      formatted = client.send(:format_messages, messages, system_prompt: "")

      expect(formatted).to eq([
                                { role: "user", parts: [{ text: "Hi" }] }
                              ])
    end

    it "formats tool result messages" do
      messages = [{ "actor" => "orchestrator", "role" => "tool", "tool_result" => {
        "name" => "file_read", "result" => { "content" => "file contents" }
      } }]
      formatted = client.send(:format_messages, messages, system_prompt: nil)
      expect(formatted.first[:role]).to eq("function")
      expect(formatted.first[:parts].first[:functionResponse]).to include(name: "file_read")
    end

    it "formats tool call messages with content" do
      messages = [{ "actor" => "orchestrator", "role" => "assistant", "content" => "Using a tool",
                    "tool_calls" => [{ "id" => "call_123", "name" => "file_read",
                                       "arguments" => { "path" => "/test.txt" } }] }]
      formatted = client.send(:format_messages, messages, system_prompt: nil)
      expect(formatted.first[:role]).to eq("model")
      expect(formatted.first[:parts].length).to eq(2)
      expect(formatted.first[:parts].first[:text]).to eq("Using a tool")
      expect(formatted.first[:parts].last[:functionCall]).to include(name: "file_read")
    end

    it "formats tool call messages without content" do
      messages = [{ "actor" => "orchestrator", "role" => "assistant", "content" => "",
                    "tool_calls" => [{ "id" => "call_456", "name" => "test_tool", "arguments" => {} }] }]
      formatted = client.send(:format_messages, messages, system_prompt: nil)
      expect(formatted.first[:role]).to eq("model")
      expect(formatted.first[:parts].length).to eq(1)
      expect(formatted.first[:parts].first[:functionCall]).to include(name: "test_tool")
    end

    it "handles tool role conversion" do
      messages = [{ "actor" => "orchestrator", "role" => "tool", "content" => "Result" }]
      formatted = client.send(:format_messages, messages, system_prompt: nil)
      expect(formatted.first[:role]).to eq("function")
    end
  end

  describe "#send_message with tools" do
    let(:tools) { [{ "name" => "file_read", "parameters" => {} }] }
    let(:gemini_response) do
      { "candidates" => [{ "content" => { "parts" => [{ "functionCall" => {
        "name" => "file_read", "args" => { "path" => "/test.txt" }
      } }] }, "finishReason" => "STOP" }],
        "usageMetadata" => { "promptTokenCount" => 50, "candidatesTokenCount" => 20 } }
    end

    before { allow(mock_gemini_client).to receive(:generate_content).and_return(gemini_response) }

    it "includes tools in request when provided" do
      expect(mock_gemini_client).to receive(:generate_content).with(
        hash_including(tools: [{ "functionDeclarations" => tools }])
      )
      client.send_message(messages: [], tools: tools)
    end

    it "extracts tool calls from response" do
      response = client.send_message(messages: [], tools: tools)
      expect(response["tool_calls"]).not_to be_nil
      expect(response["tool_calls"].first["name"]).to eq("file_read")
    end

    it "does not include tools when nil or empty" do
      expect(mock_gemini_client).to receive(:generate_content).with(hash_not_including(:tools)).twice
      client.send_message(messages: [], tools: nil)
      client.send_message(messages: [], tools: [])
    end
  end

  describe "#send_message error handling" do
    it "handles Faraday errors" do
      error = Faraday::Error.new("Connection failed")
      allow(error).to receive_messages(response: nil, response_body: nil, message: "Connection failed")
      allow(mock_gemini_client).to receive(:generate_content).and_raise(error)
      response = client.send_message(messages: [])
      expect(response).to have_key("error")
      expect(response["content"]).to include("API Error")
    end

    it "extracts error details from response" do
      error_response = { status: 401, headers: { "content-type" => "application/json" },
                         body: '{"error": "Invalid API key"}' }
      error = Faraday::UnauthorizedError.new("Unauthorized")
      allow(error).to receive(:response).and_return(error_response)
      allow(mock_gemini_client).to receive(:generate_content).and_raise(error)
      response = client.send_message(messages: [])
      expect(response["error"]["status"]).to eq(401)
      expect(response["error"]["body"]).to include("Invalid API key")
    end
  end

  describe "#max_context" do
    it "returns default max context for unknown model" do
      unknown_client = described_class.new(api_key: api_key, model: "unknown-model")
      expect(unknown_client.max_context).to eq(1_048_576)
    end
  end

  describe "#format_tools" do
    it "delegates to tool_registry" do
      tool_registry = instance_double("ToolRegistry")
      expect(tool_registry).to receive(:for_google).and_return([])
      client.format_tools(tool_registry)
    end
  end

  describe "#list_models" do
    it "returns list of available models" do
      result = client.list_models
      expect(result[:provider]).to eq("Google")
      expect(result[:models].length).to eq(3)
    end
  end

  describe "#load_api_key error handling" do
    it "raises error when file read fails" do
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_raise(StandardError.new("Permission denied"))
      expect { described_class.new }.to raise_error(Nu::Agent::Error, /Error loading API key: Permission denied/)
    end
  end

  describe "#send_request" do
    let(:internal_request) do
      {
        system_prompt: "You are a helpful assistant.",
        messages: [
          { "role" => "user", "content" => "Hello" },
          { "role" => "assistant", "content" => "Hi there!" },
          { "role" => "user", "content" => "How are you?" }
        ],
        tools: [{ "name" => "file_read", "parameters" => {} }],
        metadata: {
          rag_content: { redactions: ["secret"] },
          user_query: "How are you?"
        }
      }
    end

    let(:gemini_response) do
      {
        "candidates" => [{
          "content" => {
            "parts" => [{ "text" => "I'm doing well!" }]
          },
          "finishReason" => "STOP"
        }],
        "usageMetadata" => {
          "promptTokenCount" => 20,
          "candidatesTokenCount" => 8
        }
      }
    end

    before do
      allow(mock_gemini_client).to receive(:generate_content).and_return(gemini_response)
    end

    it "extracts and passes internal format to send_message" do
      expect(mock_gemini_client).to receive(:generate_content).with(
        hash_including(
          contents: array_including(
            hash_including(role: "user", parts: array_including(hash_including(text: "You are a helpful assistant."))),
            hash_including(role: "user", parts: array_including(hash_including(text: "Hello")))
          ),
          tools: [{ "functionDeclarations" => [{ "name" => "file_read", "parameters" => {} }] }]
        )
      )
      client.send_request(internal_request)
    end

    it "returns normalized response" do
      response = client.send_request(internal_request)

      expect(response).to include(
        "content" => "I'm doing well!",
        "model" => "gemini-2.5-flash",
        "tokens" => {
          "input" => 20,
          "output" => 8
        },
        "finish_reason" => "STOP"
      )
    end

    it "works without tools" do
      request_without_tools = internal_request.dup
      request_without_tools.delete(:tools)

      expect(mock_gemini_client).to receive(:generate_content).with(
        hash_not_including(:tools)
      )
      client.send_request(request_without_tools)
    end

    it "works without metadata" do
      request_without_metadata = internal_request.dup
      request_without_metadata.delete(:metadata)

      response = client.send_request(request_without_metadata)
      expect(response).to include("content" => "I'm doing well!")
    end

    it "handles nil system_prompt" do
      request_without_system = internal_request.dup
      request_without_system[:system_prompt] = nil

      expect(mock_gemini_client).to receive(:generate_content) do |args|
        # Should not include system prompt in contents
        contents = args[:contents]
        expect(contents).to all(satisfy { |msg| !msg[:parts][0][:text].nil? })
      end.and_return(gemini_response)

      client.send_request(request_without_system)
    end
  end
end
