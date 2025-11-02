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

  describe "tool calling loop flow" do
    let(:mock_anthropic_client) { instance_double(Anthropic::Client) }
    let(:mock_openai_client) { instance_double(OpenAI::Client) }

    let(:anthropic_tools) do
      [
        {
          "name" => "get_weather",
          "description" => "Get weather for a location",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "location" => { "type" => "string" }
            },
            "required" => ["location"]
          }
        }
      ]
    end

    let(:openai_tools) do
      [
        {
          type: "function",
          function: {
            name: "get_weather",
            description: "Get weather for a location",
            parameters: {
              type: "object",
              properties: {
                location: { type: "string" }
              },
              required: ["location"]
            }
          }
        }
      ]
    end

    before do
      allow(Anthropic::Client).to receive(:new).and_return(mock_anthropic_client)
      allow(OpenAI::Client).to receive(:new).and_return(mock_openai_client)
    end

    context "with Anthropic client" do
      let(:client) { Nu::Agent::Clients::Anthropic.new(api_key: "test_key") }

      let(:tool_call_response) do
        {
          "content" => [
            {
              "type" => "tool_use",
              "id" => "tool_123",
              "name" => "get_weather",
              "input" => { "location" => "San Francisco" }
            }
          ],
          "usage" => {
            "input_tokens" => 100,
            "output_tokens" => 50
          },
          "stop_reason" => "tool_use"
        }
      end

      let(:final_response) do
        {
          "content" => [{ "type" => "text", "text" => "The weather in San Francisco is sunny." }],
          "usage" => {
            "input_tokens" => 150,
            "output_tokens" => 20
          },
          "stop_reason" => "end_turn"
        }
      end

      before do
        allow(mock_anthropic_client).to receive(:messages).and_return(
          tool_call_response,
          final_response
        )
      end

      it "properly passes tools through all layers in tool calling flow" do
        # Step 1: Initial request with tools
        builder1 = Nu::Agent::LlmRequestBuilder.new
        request1 = builder1
                   .with_system_prompt("You are a helpful assistant.")
                   .with_user_query("What's the weather in San Francisco?")
                   .with_tools(anthropic_tools)
                   .build

        # Verify tools are in the internal format
        expect(request1[:tools]).to eq(anthropic_tools)

        # Send first request
        response1 = client.send_request(request1)

        # Verify tools were passed to the API
        expect(mock_anthropic_client).to have_received(:messages).with(
          hash_including(
            parameters: hash_including(
              tools: anthropic_tools
            )
          )
        )

        # Verify response contains tool call
        expect(response1["tool_calls"]).to be_a(Array)
        expect(response1["tool_calls"].first["name"]).to eq("get_weather")
        expect(response1["tool_calls"].first["arguments"]).to eq({ "location" => "San Francisco" })

        # Step 2: Add tool result to history and send follow-up
        history_with_tool = [
          { "actor" => "user", "role" => "user", "content" => "What's the weather in San Francisco?" },
          { "actor" => "orchestrator", "role" => "assistant", "content" => response1["content"],
            "tool_calls" => response1["tool_calls"] },
          {
            "actor" => "orchestrator",
            "role" => "tool",
            "tool_call_id" => "tool_123",
            "content" => "Sunny, 72°F",
            "tool_result" => { "name" => "get_weather", "result" => "Sunny, 72°F" }
          }
        ]

        builder2 = Nu::Agent::LlmRequestBuilder.new
        request2 = builder2
                   .with_system_prompt("You are a helpful assistant.")
                   .with_history(history_with_tool)
                   .with_tools(anthropic_tools)
                   .build

        # Verify tools still in internal format
        expect(request2[:tools]).to eq(anthropic_tools)

        # Send second request
        response2 = client.send_request(request2)

        # Verify tools were passed again and messages include tool call and result
        expect(mock_anthropic_client).to have_received(:messages).twice

        # Verify the second call included tools
        expect(mock_anthropic_client).to have_received(:messages).with(
          hash_including(
            parameters: hash_including(
              tools: anthropic_tools
            )
          )
        ).at_least(:once)

        # Verify final response
        expect(response2["content"]).to eq("The weather in San Francisco is sunny.")
      end
    end

    context "with OpenAI client" do
      let(:client) { Nu::Agent::Clients::OpenAI.new(api_key: "test_key") }

      let(:tool_call_response) do
        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                {
                  "id" => "call_123",
                  "type" => "function",
                  "function" => {
                    "name" => "get_weather",
                    "arguments" => '{"location":"San Francisco"}'
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }],
          "usage" => {
            "prompt_tokens" => 100,
            "completion_tokens" => 50
          }
        }
      end

      let(:final_response) do
        {
          "choices" => [{
            "message" => { "content" => "The weather in San Francisco is sunny." },
            "finish_reason" => "stop"
          }],
          "usage" => {
            "prompt_tokens" => 150,
            "completion_tokens" => 20
          }
        }
      end

      before do
        allow(mock_openai_client).to receive(:chat).and_return(
          tool_call_response,
          final_response
        )
      end

      it "properly passes tools through all layers in tool calling flow" do
        # Step 1: Initial request with tools
        builder1 = Nu::Agent::LlmRequestBuilder.new
        request1 = builder1
                   .with_system_prompt("You are a helpful assistant.")
                   .with_user_query("What's the weather in San Francisco?")
                   .with_tools(openai_tools)
                   .build

        # Verify tools are in the internal format
        expect(request1[:tools]).to eq(openai_tools)

        # Send first request
        response1 = client.send_request(request1)

        # Verify tools were passed to the API
        expect(mock_openai_client).to have_received(:chat).with(
          hash_including(
            parameters: hash_including(
              tools: openai_tools
            )
          )
        )

        # Verify response contains tool call
        expect(response1["tool_calls"]).to be_a(Array)
        expect(response1["tool_calls"].first["name"]).to eq("get_weather")
        expect(response1["tool_calls"].first["arguments"]).to eq({ "location" => "San Francisco" })

        # Step 2: Add tool result to history and send follow-up
        history_with_tool = [
          { "actor" => "user", "role" => "user", "content" => "What's the weather in San Francisco?" },
          { "actor" => "orchestrator", "role" => "assistant", "content" => response1["content"],
            "tool_calls" => response1["tool_calls"] },
          {
            "actor" => "orchestrator",
            "role" => "tool",
            "tool_call_id" => "call_123",
            "content" => "Sunny, 72°F",
            "tool_result" => { "name" => "get_weather", "result" => "Sunny, 72°F" }
          }
        ]

        builder2 = Nu::Agent::LlmRequestBuilder.new
        request2 = builder2
                   .with_system_prompt("You are a helpful assistant.")
                   .with_history(history_with_tool)
                   .with_tools(openai_tools)
                   .build

        # Verify tools still in internal format
        expect(request2[:tools]).to eq(openai_tools)

        # Send second request
        response2 = client.send_request(request2)

        # Verify tools were passed again
        expect(mock_openai_client).to have_received(:chat).twice

        # Verify final response
        expect(response2["content"]).to eq("The weather in San Francisco is sunny.")
      end
    end

    it "maintains tools parameter across multiple tool calls" do
      client = Nu::Agent::Clients::Anthropic.new(api_key: "test_key")

      allow(mock_anthropic_client).to receive(:messages).and_return(
        {
          "content" => [
            { "type" => "tool_use", "id" => "tool_1", "name" => "get_weather", "input" => { "location" => "SF" } }
          ],
          "usage" => { "input_tokens" => 100, "output_tokens" => 50 },
          "stop_reason" => "tool_use"
        },
        {
          "content" => [
            { "type" => "tool_use", "id" => "tool_2", "name" => "get_weather", "input" => { "location" => "NYC" } }
          ],
          "usage" => { "input_tokens" => 150, "output_tokens" => 60 },
          "stop_reason" => "tool_use"
        },
        {
          "content" => [{ "type" => "text", "text" => "Both cities have good weather." }],
          "usage" => { "input_tokens" => 200, "output_tokens" => 30 },
          "stop_reason" => "end_turn"
        }
      )

      # Call 1: Initial request with tools
      request1 = Nu::Agent::LlmRequestBuilder.new
                                             .with_system_prompt("You are a helpful assistant.")
                                             .with_user_query("Compare weather in SF and NYC")
                                             .with_tools(anthropic_tools)
                                             .build

      response1 = client.send_request(request1)

      # Call 2: Add first tool result
      history2 = [
        { "actor" => "user", "role" => "user", "content" => "Compare weather in SF and NYC" },
        { "actor" => "orchestrator", "role" => "assistant", "content" => response1["content"],
          "tool_calls" => response1["tool_calls"] },
        { "actor" => "orchestrator", "role" => "tool", "tool_call_id" => "tool_1", "content" => "Sunny",
          "tool_result" => { "name" => "get_weather", "result" => "Sunny" } }
      ]

      request2 = Nu::Agent::LlmRequestBuilder.new
                                             .with_system_prompt("You are a helpful assistant.")
                                             .with_history(history2)
                                             .with_tools(anthropic_tools)
                                             .build

      response2 = client.send_request(request2)

      # Call 3: Add second tool result
      history3 = history2 + [
        { "actor" => "orchestrator", "role" => "assistant", "content" => response2["content"],
          "tool_calls" => response2["tool_calls"] },
        { "actor" => "orchestrator", "role" => "tool", "tool_call_id" => "tool_2", "content" => "Rainy",
          "tool_result" => { "name" => "get_weather", "result" => "Rainy" } }
      ]

      request3 = Nu::Agent::LlmRequestBuilder.new
                                             .with_system_prompt("You are a helpful assistant.")
                                             .with_history(history3)
                                             .with_tools(anthropic_tools)
                                             .build

      response3 = client.send_request(request3)

      # Verify tools parameter was passed in all three calls
      expect(mock_anthropic_client).to have_received(:messages).with(
        hash_including(parameters: hash_including(tools: anthropic_tools))
      ).exactly(3).times

      # Verify final response
      expect(response3["content"]).to eq("Both cities have good weather.")
    end
  end

  describe "debug output verbosity" do
    let(:console) { StringIO.new }
    let(:mock_db) { instance_double(Nu::Agent::History) }
    let(:application) { instance_double(Nu::Agent::Application, debug: true, history: mock_db) }
    let(:formatter) { Nu::Agent::Formatters::LlmRequestFormatter.new(console: console, application: application) }

    let(:internal_request) do
      {
        system_prompt: "You are a helpful assistant.",
        messages: [
          { "actor" => "user", "role" => "user", "content" => "First question" },
          { "actor" => "orchestrator", "role" => "assistant", "content" => "First response" },
          { "actor" => "user", "role" => "user", "content" => "Second question" }
        ],
        tools: [
          {
            "name" => "test_tool",
            "description" => "A test tool",
            "input_schema" => {
              "type" => "object",
              "properties" => { "arg" => { "type" => "string" } }
            }
          }
        ],
        metadata: {
          rag_content: {
            redactions: ["secret"],
            spell_check: { "wrng" => "wrong" }
          },
          conversation_id: 1,
          exchange_id: 2
        }
      }
    end

    it "displays nothing at verbosity level 0" do
      allow(mock_db).to receive(:get_int).with("llm_verbosity", default: 0).and_return(0)

      formatter.display_yaml(internal_request)
      output = console.string

      expect(output).to be_empty
    end

    it "displays only final user message at verbosity level 1" do
      allow(mock_db).to receive(:get_int).with("llm_verbosity", default: 0).and_return(1)

      formatter.display_yaml(internal_request)
      output = console.string

      # Should contain final message
      expect(output).to include("final_message")
      expect(output).to include("Second question")

      # Should NOT contain system prompt, rag content, tools, or full history
      expect(output).not_to include("system_prompt")
      expect(output).not_to include("rag_content")
      expect(output).not_to include("tools")
      expect(output).not_to include("First question")
    end

    it "displays final message and system prompt at verbosity level 2" do
      allow(mock_db).to receive(:get_int).with("llm_verbosity", default: 0).and_return(2)

      formatter.display_yaml(internal_request)
      output = console.string

      # Should contain final message and system prompt
      expect(output).to include("final_message")
      expect(output).to include("Second question")
      expect(output).to include("system_prompt")
      expect(output).to include("You are a helpful assistant")

      # Should NOT contain rag content, tools, or full history
      expect(output).not_to include("rag_content")
      expect(output).not_to include("tools")
      expect(output).not_to include("First question")
    end

    it "displays final message, system prompt, and rag content at verbosity level 3" do
      allow(mock_db).to receive(:get_int).with("llm_verbosity", default: 0).and_return(3)

      formatter.display_yaml(internal_request)
      output = console.string

      # Should contain final message, system prompt, and rag content
      expect(output).to include("final_message")
      expect(output).to include("system_prompt")
      expect(output).to include("rag_content")
      expect(output).to include("redactions")
      expect(output).to include("spell_check")

      # Should NOT contain tools or full history
      expect(output).not_to include("tools")
      expect(output).not_to include("First question")
    end

    it "displays final message, system prompt, rag content, and tools at verbosity level 4" do
      allow(mock_db).to receive(:get_int).with("llm_verbosity", default: 0).and_return(4)

      formatter.display_yaml(internal_request)
      output = console.string

      # Should contain final message, system prompt, rag content, and tools
      expect(output).to include("final_message")
      expect(output).to include("system_prompt")
      expect(output).to include("rag_content")
      expect(output).to include("tools")
      expect(output).to include("test_tool")

      # Should NOT contain full history (only final message)
      expect(output).not_to include("First question")
    end

    it "displays full tool definitions at verbosity level 5" do
      allow(mock_db).to receive(:get_int).with("llm_verbosity", default: 0).and_return(5)

      formatter.display_yaml(internal_request)
      output = console.string

      # Should contain system_prompt, rag_content, and full tool definitions
      expect(output).to include("system_prompt")
      expect(output).to include("rag_content")
      expect(output).to include("tools")
      expect(output).to include("test_tool")
      expect(output).to include("A test tool")

      # Should NOT include full message history yet (that's level 6)
      expect(output).not_to include("messages:")
      expect(output).to include("final_message")
    end

    it "displays full message history at verbosity level 6" do
      allow(mock_db).to receive(:get_int).with("llm_verbosity", default: 0).and_return(6)

      formatter.display_yaml(internal_request)
      output = console.string

      # Should contain everything including full message history
      expect(output).to include("messages")
      expect(output).to include("system_prompt")
      expect(output).to include("rag_content")
      expect(output).to include("tools")

      # Should include ALL messages in history
      expect(output).to include("First question")
      expect(output).to include("First response")
      expect(output).to include("Second question")

      # Should NOT have separate final_message when showing full messages
      expect(output).not_to include("final_message")
    end

    it "properly formats YAML output with gray color codes" do
      allow(mock_db).to receive(:get_int).with("llm_verbosity", default: 0).and_return(1)

      formatter.display_yaml(internal_request)
      output = console.string

      # Should include gray color codes (\e[90m) and reset codes (\e[0m)
      expect(output).to include("\e[90m")
      expect(output).to include("\e[0m")
    end

    it "handles nil rag_content gracefully" do
      allow(mock_db).to receive(:get_int).with("llm_verbosity", default: 0).and_return(3)

      request_without_rag = internal_request.dup
      request_without_rag[:metadata] = { conversation_id: 1 }

      formatter.display_yaml(request_without_rag)
      output = console.string

      # Should not crash and should not show rag_content if it's nil
      expect(output).to include("final_message")
      expect(output).not_to include("rag_content")
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/ExampleLength
