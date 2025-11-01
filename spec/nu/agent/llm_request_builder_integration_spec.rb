# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass, RSpec/ExampleLength
RSpec.describe "LLM Request Builder Integration" do
  describe "multi-turn conversation flow" do
    let(:mock_anthropic_client) { instance_double(Anthropic::Client) }
    let(:mock_openai_client) { instance_double(OpenAI::Client) }
    let(:mock_gemini_client) { double("Gemini") }

    let(:anthropic_tools) do
      [
        {
          "name" => "test_tool",
          "description" => "A test tool",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "arg" => { "type" => "string" }
            }
          }
        }
      ]
    end

    let(:openai_tools) do
      [
        {
          type: "function",
          function: {
            name: "test_tool",
            description: "A test tool",
            parameters: {
              type: "object",
              properties: {
                arg: { type: "string" }
              }
            }
          }
        }
      ]
    end

    let(:google_tools) do
      [
        {
          "name" => "test_tool",
          "description" => "A test tool",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "arg" => { "type" => "string" }
            }
          }
        }
      ]
    end

    let(:history_messages) do
      [
        { "actor" => "user", "role" => "user", "content" => "First question" },
        { "actor" => "orchestrator", "role" => "assistant", "content" => "First response" }
      ]
    end

    before do
      allow(Anthropic::Client).to receive(:new).and_return(mock_anthropic_client)
      allow(OpenAI::Client).to receive(:new).and_return(mock_openai_client)
      allow(Gemini).to receive(:new).and_return(mock_gemini_client)
    end

    context "with Anthropic client" do
      let(:client) { Nu::Agent::Clients::Anthropic.new(api_key: "test_key") }

      let(:anthropic_response) do
        {
          "content" => [{ "type" => "text", "text" => "Response from Anthropic" }],
          "usage" => {
            "input_tokens" => 100,
            "output_tokens" => 50
          },
          "stop_reason" => "end_turn"
        }
      end

      before do
        allow(mock_anthropic_client).to receive(:messages).and_return(anthropic_response)
      end

      it "handles multi-turn conversation with internal format" do
        # Build internal request
        builder = Nu::Agent::LlmRequestBuilder.new
        internal_request = builder
                           .with_system_prompt("You are a helpful assistant.")
                           .with_history(history_messages)
                           .with_user_query("Second question")
                           .with_tools(anthropic_tools)
                           .with_metadata(conversation_id: 1, exchange_id: 2)
                           .build

        # Verify internal format structure
        expect(internal_request).to include(
          system_prompt: "You are a helpful assistant.",
          messages: array_including(
            hash_including("content" => "First question"),
            hash_including("content" => "First response"),
            hash_including("content" => "Second question")
          ),
          tools: anthropic_tools,
          metadata: hash_including(conversation_id: 1, exchange_id: 2)
        )

        # Send request through client
        response = client.send_request(internal_request)

        # Verify client called with correct format
        expect(mock_anthropic_client).to have_received(:messages) do |args|
          params = args[:parameters]
          expect(params[:system]).to eq("You are a helpful assistant.")
          expect(params[:messages]).to include(
            { role: "user", content: "First question" },
            { role: "assistant", content: "First response" },
            { role: "user", content: "Second question" }
          )
          expect(params[:tools]).not_to be_empty
        end

        # Verify response is normalized
        expect(response).to include(
          "content" => "Response from Anthropic",
          "tokens" => hash_including("input" => 100, "output" => 50)
        )
      end
    end

    context "with OpenAI client" do
      let(:client) { Nu::Agent::Clients::OpenAI.new(api_key: "test_key") }

      let(:openai_response) do
        {
          "choices" => [{
            "message" => { "content" => "Response from OpenAI" },
            "finish_reason" => "stop"
          }],
          "usage" => {
            "prompt_tokens" => 100,
            "completion_tokens" => 50
          }
        }
      end

      before do
        allow(mock_openai_client).to receive(:chat).and_return(openai_response)
      end

      it "handles multi-turn conversation with internal format" do
        # Build internal request
        builder = Nu::Agent::LlmRequestBuilder.new
        internal_request = builder
                           .with_system_prompt("You are a helpful assistant.")
                           .with_history(history_messages)
                           .with_user_query("Second question")
                           .with_tools(openai_tools)
                           .with_metadata(conversation_id: 1, exchange_id: 2)
                           .build

        # Send request through client
        response = client.send_request(internal_request)

        # Verify client called with correct format (OpenAI puts system as first message)
        expect(mock_openai_client).to have_received(:chat) do |args|
          messages = args[:parameters][:messages]
          expect(messages.first[:role]).to eq("system")
          expect(messages.first[:content]).to eq("You are a helpful assistant.")
          expect(messages).to include(
            { role: "user", content: "First question" },
            { role: "assistant", content: "First response" },
            { role: "user", content: "Second question" }
          )
          expect(args[:parameters][:tools]).to eq(openai_tools)
        end

        # Verify response is normalized
        expect(response).to include(
          "content" => "Response from OpenAI",
          "tokens" => hash_including("input" => 100, "output" => 50)
        )
      end
    end

    context "with Google client" do
      let(:client) { Nu::Agent::Clients::Google.new(api_key: "test_key") }

      let(:gemini_response) do
        {
          "candidates" => [{
            "content" => {
              "parts" => [{ "text" => "Response from Google" }]
            },
            "finishReason" => "STOP"
          }],
          "usageMetadata" => {
            "promptTokenCount" => 100,
            "candidatesTokenCount" => 50
          }
        }
      end

      before do
        allow(mock_gemini_client).to receive(:generate_content).and_return(gemini_response)
      end

      it "handles multi-turn conversation with internal format" do
        # Build internal request
        builder = Nu::Agent::LlmRequestBuilder.new
        internal_request = builder
                           .with_system_prompt("You are a helpful assistant.")
                           .with_history(history_messages)
                           .with_user_query("Second question")
                           .with_tools(google_tools)
                           .with_metadata(conversation_id: 1, exchange_id: 2)
                           .build

        # Send request through client
        response = client.send_request(internal_request)

        # Verify client called with correct format
        expect(mock_gemini_client).to have_received(:generate_content) do |args|
          # Google embeds system prompt as first user message
          contents = args[:contents]
          expect(contents.first).to eq({ role: "user", parts: [{ text: "You are a helpful assistant." }] })
          expect(contents.map { |c| c[:role] }).to eq(%w[user user model user])
          expect(contents[1..].map { |c| c[:parts].first[:text] }).to eq(
            ["First question", "First response", "Second question"]
          )
          expect(args[:tools]).to eq([{ "functionDeclarations" => google_tools }])
        end

        # Verify response is normalized
        expect(response).to include(
          "content" => "Response from Google",
          "tokens" => hash_including("input" => 100, "output" => 50)
        )
      end
    end

    context "with XAI client" do
      let(:client) { Nu::Agent::Clients::XAI.new(api_key: "test_key") }

      let(:xai_response) do
        {
          "choices" => [{
            "message" => { "content" => "Response from XAI" },
            "finish_reason" => "stop"
          }],
          "usage" => {
            "prompt_tokens" => 100,
            "completion_tokens" => 50
          }
        }
      end

      before do
        allow(mock_openai_client).to receive(:chat).and_return(xai_response)
      end

      it "handles multi-turn conversation with internal format" do
        # Build internal request
        builder = Nu::Agent::LlmRequestBuilder.new
        internal_request = builder
                           .with_system_prompt("You are a helpful assistant.")
                           .with_history(history_messages)
                           .with_user_query("Second question")
                           .with_tools(openai_tools)
                           .with_metadata(conversation_id: 1, exchange_id: 2)
                           .build

        # Send request through client (XAI inherits from OpenAI)
        response = client.send_request(internal_request)

        # Verify client called with correct format
        expect(mock_openai_client).to have_received(:chat) do |args|
          messages = args[:parameters][:messages]
          expect(messages.first[:role]).to eq("system")
          expect(messages.first[:content]).to eq("You are a helpful assistant.")
          expect(messages).to include(
            { role: "user", content: "First question" },
            { role: "assistant", content: "First response" },
            { role: "user", content: "Second question" }
          )
          expect(args[:parameters][:tools]).to eq(openai_tools)
        end

        # Verify response is normalized
        expect(response).to include(
          "content" => "Response from XAI",
          "tokens" => hash_including("input" => 100, "output" => 50)
        )
      end
    end

    it "maintains conversation continuity across multiple turns" do
      client = Nu::Agent::Clients::Anthropic.new(api_key: "test_key")

      allow(mock_anthropic_client).to receive(:messages).and_return(
        {
          "content" => [{ "type" => "text", "text" => "Turn 2 response" }],
          "usage" => { "input_tokens" => 100, "output_tokens" => 50 },
          "stop_reason" => "end_turn"
        },
        {
          "content" => [{ "type" => "text", "text" => "Turn 3 response" }],
          "usage" => { "input_tokens" => 150, "output_tokens" => 60 },
          "stop_reason" => "end_turn"
        }
      )

      # Turn 1: Already in history
      # Turn 2: Add new user message
      builder2 = Nu::Agent::LlmRequestBuilder.new
      request2 = builder2
                 .with_system_prompt("You are a helpful assistant.")
                 .with_history(history_messages)
                 .with_user_query("Second question")
                 .build

      response2 = client.send_request(request2)
      expect(response2["content"]).to eq("Turn 2 response")

      # Turn 3: Add turn 2 to history and ask new question
      history_with_turn2 = history_messages + [
        { "actor" => "user", "role" => "user", "content" => "Second question" },
        { "actor" => "orchestrator", "role" => "assistant", "content" => "Turn 2 response" }
      ]

      builder3 = Nu::Agent::LlmRequestBuilder.new
      request3 = builder3
                 .with_system_prompt("You are a helpful assistant.")
                 .with_history(history_with_turn2)
                 .with_user_query("Third question")
                 .build

      response3 = client.send_request(request3)
      expect(response3["content"]).to eq("Turn 3 response")

      # Verify messages method was called twice
      expect(mock_anthropic_client).to have_received(:messages).twice

      # Verify the third request included all 5 messages (2 original + 2 from turn 2 + 1 new)
      expect(mock_anthropic_client).to have_received(:messages).with(
        hash_including(
          parameters: hash_including(
            messages: array_including(
              { role: "user", content: "First question" },
              { role: "assistant", content: "First response" },
              { role: "user", content: "Second question" },
              { role: "assistant", content: "Turn 2 response" },
              { role: "user", content: "Third question" }
            )
          )
        )
      ).once
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/ExampleLength
