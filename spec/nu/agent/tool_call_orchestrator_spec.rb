# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::ToolCallOrchestrator do
  let(:client) { instance_double(Nu::Agent::Clients::Anthropic, model: "claude-sonnet-4-5") }
  let(:history) { instance_double(Nu::Agent::History) }
  let(:formatter) { instance_double(Nu::Agent::Formatter) }
  let(:console) { instance_double(Nu::Agent::ConsoleIO) }
  let(:tool_registry) { instance_double(Nu::Agent::ToolRegistry) }
  let(:application) { instance_double(Nu::Agent::Application) }

  let(:orchestrator) do
    described_class.new(
      client: client,
      history: history,
      formatter: formatter,
      console: console,
      conversation_id: 1,
      exchange_id: 1,
      tool_registry: tool_registry,
      application: application
    )
  end

  describe "#execute" do
    let(:messages) { [{ "role" => "user", "content" => "Hello" }] }
    let(:tools) { [] }

    context "when API returns an error" do
      it "saves error message and returns error result" do
        error_response = {
          "error" => "API Error",
          "content" => "Error message",
          "model" => "claude-sonnet-4-5"
        }

        allow(client).to receive(:send_message).and_return(error_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)

        result = orchestrator.execute(messages: messages, tools: tools)

        expect(result[:error]).to be true
        expect(result[:response]).to eq(error_response)
        expect(history).to have_received(:add_message).with(
          hash_including(
            actor: "api_error",
            role: "assistant",
            redacted: false
          )
        )
      end
    end

    context "when LLM responds without tool calls" do
      it "returns final response with metrics" do
        final_response = {
          "content" => "Hello there!",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001
        }

        allow(client).to receive(:send_message).and_return(final_response)

        result = orchestrator.execute(messages: messages, tools: tools)

        expect(result[:error]).to be false
        expect(result[:response]).to eq(final_response)
        expect(result[:metrics][:tokens_input]).to eq(10)
        expect(result[:metrics][:tokens_output]).to eq(5)
        expect(result[:metrics][:spend]).to eq(0.001)
        expect(result[:metrics][:message_count]).to eq(1)
      end
    end

    context "when LLM makes tool calls" do
      it "executes tools and continues loop until final response" do
        tool_call_response = {
          "content" => "Let me check that",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "test_tool", "arguments" => { "arg" => "value" } }
          ]
        }

        final_response = {
          "content" => "Here's the result",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(console).to receive(:hide_spinner)
        allow(console).to receive(:show_spinner)
        allow(application).to receive(:send).with(:output_line, "Let me check that")
        allow(tool_registry).to receive(:execute).and_return("tool result")

        result = orchestrator.execute(messages: messages, tools: tools)

        expect(result[:error]).to be false
        expect(result[:response]).to eq(final_response)
        expect(result[:metrics][:tool_call_count]).to eq(1)
        expect(result[:metrics][:message_count]).to eq(2)
        expect(tool_registry).to have_received(:execute).with(
          name: "test_tool",
          arguments: { "arg" => "value" },
          history: history,
          context: hash_including("conversation_id" => 1)
        )
      end

      it "handles empty content in tool call response" do
        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "test_tool", "arguments" => {} }
          ]
        }

        final_response = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(console).to receive(:hide_spinner)
        allow(console).to receive(:show_spinner)
        allow(tool_registry).to receive(:execute).and_return("result")

        result = orchestrator.execute(messages: messages, tools: tools)

        expect(result[:error]).to be false
        # Should not try to hide/show spinner when content is empty
        expect(console).not_to have_received(:hide_spinner)
      end
    end

    context "when handling metrics" do
      it "accumulates tokens and spend across multiple calls" do
        response1 = {
          "content" => "Thinking",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [{ "id" => "call_1", "name" => "tool", "arguments" => {} }]
        }

        response2 = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 20, "output" => 10 },
          "spend" => 0.002
        }

        allow(client).to receive(:send_message).and_return(response1, response2)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(console).to receive(:hide_spinner)
        allow(console).to receive(:show_spinner)
        allow(application).to receive(:send).with(:output_line, "Thinking")
        allow(tool_registry).to receive(:execute).and_return("result")

        result = orchestrator.execute(messages: messages, tools: tools)

        # tokens_input should be max, tokens_output should be sum
        expect(result[:metrics][:tokens_input]).to eq(20)
        expect(result[:metrics][:tokens_output]).to eq(15)
        expect(result[:metrics][:spend]).to eq(0.003)
      end

      it "handles nil token values gracefully" do
        response = {
          "content" => "Hello",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => nil, "output" => nil },
          "spend" => nil
        }

        allow(client).to receive(:send_message).and_return(response)

        result = orchestrator.execute(messages: messages, tools: tools)

        expect(result[:metrics][:tokens_input]).to eq(0)
        expect(result[:metrics][:tokens_output]).to eq(0)
        expect(result[:metrics][:spend]).to eq(0.0)
      end
    end
  end
end
