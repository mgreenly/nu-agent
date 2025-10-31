# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::ToolCallOrchestrator do
  let(:client) { instance_double(Nu::Agent::Clients::Anthropic, model: "claude-sonnet-4-5") }
  let(:history) { instance_double(Nu::Agent::History) }
  let(:formatter) { instance_double(Nu::Agent::Formatter) }
  let(:console) { instance_double(Nu::Agent::ConsoleIO) }
  let(:tool_registry) do
    instance_double(Nu::Agent::ToolRegistry).tap do |registry|
      # Stub metadata_for to return default metadata for all tools
      allow(registry).to receive(:metadata_for).and_return({
        operation_type: :read,
        scope: :confined
      })
    end
  end
  let(:application) { instance_double(Nu::Agent::Application, formatter: formatter, console: console) }

  let(:orchestrator) do
    described_class.new(
      client: client,
      history: history,
      exchange_info: { conversation_id: 1, exchange_id: 1 },
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

    context "parallel execution integration" do
      it "works correctly with single tool call" do
        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/path/to/file" } }
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
        allow(tool_registry).to receive(:execute).and_return("file contents")

        result = orchestrator.execute(messages: messages, tools: tools)

        expect(result[:error]).to be false
        expect(result[:metrics][:tool_call_count]).to eq(1)
        expect(tool_registry).to have_received(:execute).once
      end

      it "executes multiple independent tools" do
        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/path/to/file1" } },
            { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "/path/to/file2" } },
            { "id" => "call_3", "name" => "file_read", "arguments" => { "file" => "/path/to/file3" } }
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
        allow(tool_registry).to receive(:execute).and_return("file contents")

        result = orchestrator.execute(messages: messages, tools: tools)

        expect(result[:error]).to be false
        expect(result[:metrics][:tool_call_count]).to eq(3)
        expect(tool_registry).to have_received(:execute).exactly(3).times
      end

      it "saves tool results to history in correct order" do
        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/path/to/file1" } },
            { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "/path/to/file2" } }
          ]
        }

        final_response = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        saved_tool_call_ids = []
        allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
        allow(formatter).to receive(:display_message_created)
        allow(history).to receive(:add_message) do |params|
          saved_tool_call_ids << params[:tool_call_id] if params[:role] == "tool"
        end
        allow(tool_registry).to receive(:execute).and_return("file contents")

        orchestrator.execute(messages: messages, tools: tools)

        # Results should be saved in the same order as tool calls
        expect(saved_tool_call_ids).to eq(["call_1", "call_2"])
      end

      it "displays tool results in correct order" do
        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/path/to/file1" } },
            { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "/path/to/file2" } }
          ]
        }

        final_response = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        displayed_tool_names = []
        allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created) do |params|
          displayed_tool_names << params[:tool_result]["name"] if params[:role] == "tool"
        end
        allow(tool_registry).to receive(:execute).and_return("file contents")

        orchestrator.execute(messages: messages, tools: tools)

        # Results should be displayed in the same order as tool calls
        expect(displayed_tool_names).to eq(["file_read", "file_read"])
      end

      it "updates messages list with tool results in correct order" do
        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/path/to/file1" } },
            { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "/path/to/file2" } }
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
        allow(tool_registry).to receive(:execute).and_return("file contents")

        local_messages = [{ "role" => "user", "content" => "Hello" }]
        orchestrator.execute(messages: local_messages, tools: tools)

        # Find tool result messages in the messages array
        tool_results = local_messages.select { |m| m["role"] == "tool" }
        expect(tool_results.length).to eq(2)
        expect(tool_results[0]["tool_call_id"]).to eq("call_1")
        expect(tool_results[1]["tool_call_id"]).to eq("call_2")
      end

      it "handles dependent tools in correct order" do
        # Write followed by read on same file - should execute sequentially
        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "file_write", "arguments" => { "file" => "/path/to/file", "content" => "new content" } },
            { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "/path/to/file" } }
          ]
        }

        final_response = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        execution_order = []
        allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(tool_registry).to receive(:execute) do |params|
          execution_order << params[:name]
          params[:name] == "file_write" ? "written" : "new content"
        end

        orchestrator.execute(messages: messages, tools: tools)

        # Write must complete before read
        expect(execution_order).to eq(["file_write", "file_read"])
      end
    end
  end
end
