# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::ToolCallOrchestrator do
  let(:client) { instance_double(Nu::Agent::Clients::Anthropic, model: "claude-sonnet-4-5", name: "Anthropic") }
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
  let(:application) do
    instance_double(Nu::Agent::Application, formatter: formatter, console: console, debug: false)
  end

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

    context "when calling client" do
      it "passes internal format to client.send_request as single hash argument" do
        final_response = {
          "content" => "Hello there!",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001
        }

        system_prompt = "You are a helpful assistant"

        # Verify client receives a single hash arg, not keyword args
        # Current implementation uses **params which would fail this
        allow(client).to receive(:send_request) do |arg|
          # Fail if called with keyword arguments instead of single hash
          raise "Expected hash argument, got keyword args" unless arg.is_a?(Hash)

          expect(arg[:messages]).to eq(messages)
          expect(arg[:tools]).to eq(tools)
          expect(arg[:system_prompt]).to eq(system_prompt)
          final_response
        end

        orchestrator.execute(messages: messages, tools: tools, system_prompt: system_prompt)
      end
    end

    context "when API returns an error" do
      it "saves error message and returns error result" do
        error_response = {
          "error" => "API Error",
          "content" => "Error message",
          "model" => "claude-sonnet-4-5"
        }

        allow(client).to receive(:send_request).and_return(error_response)
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

        allow(client).to receive(:send_request).and_return(final_response)

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

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
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

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
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

        allow(client).to receive(:send_request).and_return(response1, response2)
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

        allow(client).to receive(:send_request).and_return(response)

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

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
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

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
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
        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(formatter).to receive(:display_message_created)
        allow(history).to receive(:add_message) do |params|
          saved_tool_call_ids << params[:tool_call_id] if params[:role] == "tool"
        end
        allow(tool_registry).to receive(:execute).and_return("file contents")

        orchestrator.execute(messages: messages, tools: tools)

        # Results should be saved in the same order as tool calls
        expect(saved_tool_call_ids).to eq(%w[call_1 call_2])
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
        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created) do |params|
          displayed_tool_names << params[:tool_result]["name"] if params[:role] == "tool"
        end
        allow(tool_registry).to receive(:execute).and_return("file contents")

        orchestrator.execute(messages: messages, tools: tools)

        # Results should be displayed in the same order as tool calls
        expect(displayed_tool_names).to eq(%w[file_read file_read])
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

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
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
            { "id" => "call_1", "name" => "file_write",
              "arguments" => { "file" => "/path/to/file", "content" => "new content" } },
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
        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(tool_registry).to receive(:execute) do |params|
          execution_order << params[:name]
          params[:name] == "file_write" ? "written" : "new content"
        end

        orchestrator.execute(messages: messages, tools: tools)

        # Write must complete before read
        expect(execution_order).to eq(%w[file_write file_read])
      end
    end

    context "debug and verbosity features" do
      let(:application) do
        instance_double(Nu::Agent::Application, formatter: formatter, console: console, debug: true)
      end
      let(:tool_call_formatter) { instance_double("ToolCallFormatter") }
      let(:tool_result_formatter) { instance_double("ToolResultFormatter") }

      before do
        allow(formatter).to receive(:instance_variable_get).with(:@tool_call_formatter).and_return(tool_call_formatter)
        allow(formatter).to receive(:instance_variable_get)
          .with(:@tool_result_formatter).and_return(tool_result_formatter)
        allow(tool_call_formatter).to receive(:display)
        allow(tool_result_formatter).to receive(:display)
        allow(application).to receive(:output_line)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(2)
      end

      it "displays debug output with batch and thread context when debug is enabled" do
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

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(tool_registry).to receive(:execute).and_return("file contents")

        orchestrator.execute(messages: messages, tools: tools)

        # Should display batch planning debug output
        expect(application).to have_received(:output_line).with(
          /Analyzing.*tool calls for dependencies/,
          type: :debug
        )
        expect(application).to have_received(:output_line).with(
          /Created.*batch/,
          type: :debug
        )

        # Should call tool_call_formatter with batch/thread context
        expect(tool_call_formatter).to have_received(:display).with(
          hash_including("id" => "call_1"),
          hash_including(batch: 1, thread: 1)
        )

        # Should call tool_result_formatter with batch/thread context (once for each tool)
        expect(tool_result_formatter).to have_received(:display).with(
          hash_including("tool_result"),
          hash_including(:batch, :thread, :start_time, :duration)
        ).at_least(:once)
      end

      it "displays singular text for single batch and tool" do
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

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(tool_registry).to receive(:execute).and_return("file contents")

        orchestrator.execute(messages: messages, tools: tools)

        # Should use singular form
        expect(application).to have_received(:output_line).with(
          /Created 1 batch from 1 tool call/,
          type: :debug
        )
        expect(application).to have_received(:output_line).with(
          /Batch 1: 1 tool.*parallel execution/,
          type: :debug
        )
      end

      it "displays plural text for multiple batches and tools" do
        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/file1" } },
            { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "/file2" } }
          ]
        }

        final_response = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(tool_registry).to receive(:execute).and_return("file contents")

        orchestrator.execute(messages: messages, tools: tools)

        # Should use plural form
        expect(application).to have_received(:output_line).with(
          /Created 1 batch from 2 tool calls/,
          type: :debug
        )
        expect(application).to have_received(:output_line).with(
          /Batch 1: 2 tools/,
          type: :debug
        )
      end

      it "displays barrier tool batch type" do
        # Configure tool_registry to return barrier metadata for execute_bash
        allow(tool_registry).to receive(:metadata_for).with("execute_bash").and_return({
                                                                                         operation_type: :write,
                                                                                         scope: :unconfined
                                                                                       })

        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "execute_bash", "arguments" => { "command" => "ls" } }
          ]
        }

        final_response = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(tool_registry).to receive(:execute).and_return("output")

        orchestrator.execute(messages: messages, tools: tools)

        # Should display BARRIER type
        expect(application).to have_received(:output_line).with(
          /BARRIER.*runs alone/,
          type: :debug
        )
      end

      it "displays parallel execution when tool has no metadata" do
        # Configure tool_registry to return nil metadata
        allow(tool_registry).to receive(:metadata_for).with("unknown_tool").and_return(nil)

        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "unknown_tool", "arguments" => {} }
          ]
        }

        final_response = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(tool_registry).to receive(:execute).and_return("output")

        orchestrator.execute(messages: messages, tools: tools)

        # Should display parallel execution type (not barrier)
        expect(application).to have_received(:output_line).with(
          /parallel execution/,
          type: :debug
        )
      end
    end

    context "content display" do
      before do
        allow(console).to receive(:hide_spinner)
        allow(console).to receive(:show_spinner)
      end

      it "displays content when non-empty" do
        tool_call_response = {
          "content" => "Let me check that for you",
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

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(tool_registry).to receive(:execute).and_return("file contents")

        orchestrator.execute(messages: messages, tools: tools)

        # Should hide and show spinner when content is present
        expect(console).to have_received(:hide_spinner).at_least(:once)
        expect(console).to have_received(:show_spinner).with("Thinking...").at_least(:once)
      end

      it "does not display when content is whitespace only" do
        tool_call_response = {
          "content" => "   \n  ",
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

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
        allow(tool_registry).to receive(:execute).and_return("file contents")

        orchestrator.execute(messages: messages, tools: tools)

        # Should not hide/show spinner for whitespace-only content
        expect(console).not_to have_received(:hide_spinner)
        expect(console).not_to have_received(:show_spinner)
      end
    end

    context "system prompt handling" do
      it "includes system prompt when provided" do
        allow(client).to receive(:send_request) do |params|
          expect(params[:system_prompt]).to eq("You are a helpful assistant")
          {
            "content" => "Hello",
            "model" => "claude-sonnet-4-5",
            "tokens" => { "input" => 10, "output" => 5 },
            "spend" => 0.001
          }
        end

        orchestrator.execute(
          messages: messages,
          tools: tools,
          system_prompt: "You are a helpful assistant"
        )

        expect(client).to have_received(:send_request).with(
          hash_including(system_prompt: "You are a helpful assistant")
        )
      end

      it "does not include system prompt when not provided" do
        allow(client).to receive(:send_request) do |params|
          expect(params).not_to have_key(:system_prompt)
          {
            "content" => "Hello",
            "model" => "claude-sonnet-4-5",
            "tokens" => { "input" => 10, "output" => 5 },
            "spend" => 0.001
          }
        end

        orchestrator.execute(messages: messages, tools: tools)

        expect(client).to have_received(:send_request)
      end
    end

    context "edge cases for branch coverage" do
      let(:tool_call_formatter) { instance_double("ToolCallFormatter") }
      let(:tool_result_formatter) { instance_double("ToolResultFormatter") }

      before do
        allow(formatter).to receive(:instance_variable_get).with(:@tool_call_formatter).and_return(tool_call_formatter)
        allow(formatter).to receive(:instance_variable_get)
          .with(:@tool_result_formatter).and_return(tool_result_formatter)
        allow(tool_call_formatter).to receive(:display)
        allow(tool_result_formatter).to receive(:display)
        allow(history).to receive(:add_message)
        allow(formatter).to receive(:display_message_created)
      end

      it "handles tool call not found in index (line 207)" do
        # This tests the else branch of the safe navigation operator when tool call is not found
        application_with_debug = instance_double(Nu::Agent::Application,
                                                 formatter: formatter,
                                                 console: console,
                                                 debug: true)
        allow(application_with_debug).to receive(:output_line)

        orchestrator_with_debug = described_class.new(
          client: client,
          history: history,
          exchange_info: { conversation_id: 1, exchange_id: 1 },
          tool_registry: tool_registry,
          application: application_with_debug
        )

        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/file1" } }
          ]
        }

        final_response = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(2)
        allow(tool_registry).to receive(:execute).and_return("file contents")

        # Mock the display_tool_call_with_context to call find_tool_call_index with wrong ID
        allow(tool_call_formatter).to receive(:display) do |tool_call, _context|
          # Simulate a scenario where we try to find a tool call that doesn't exist
          # This will trigger the safe navigation else branch
          orchestrator_with_debug.send(:find_tool_call_index, [], tool_call)
        end

        orchestrator_with_debug.execute(messages: messages, tools: tools)

        # The test passes if no error is raised and index defaults to 0
        expect(tool_call_formatter).to have_received(:display)
      end

      it "handles verbosity level 1 for debug output (line 312)" do
        # Test when verbosity is 1, which should trigger early return in output_debug for verbosity 2
        application_with_debug = instance_double(Nu::Agent::Application,
                                                 formatter: formatter,
                                                 console: console,
                                                 debug: true)
        allow(application_with_debug).to receive(:output_line)

        orchestrator_with_debug = described_class.new(
          client: client,
          history: history,
          exchange_info: { conversation_id: 1, exchange_id: 1 },
          tool_registry: tool_registry,
          application: application_with_debug
        )

        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/file1" } }
          ]
        }

        final_response = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(1)
        allow(tool_registry).to receive(:execute).and_return("file contents")

        orchestrator_with_debug.execute(messages: messages, tools: tools)

        # Should output batch count summary (verbosity 1) but not API debug messages (verbosity 2)
        expect(application_with_debug).to have_received(:output_line).with(
          /Created.*batch/,
          type: :debug
        )
        expect(application_with_debug).not_to have_received(:output_line).with(
          /API Request/,
          type: :debug
        )
      end

      it "skips detailed batch info when verbosity < 2 (line 322)" do
        # Test when verbosity is 1, detailed batch info should be skipped
        application_with_debug = instance_double(Nu::Agent::Application,
                                                 formatter: formatter,
                                                 console: console,
                                                 debug: true)
        allow(application_with_debug).to receive(:output_line)

        orchestrator_with_debug = described_class.new(
          client: client,
          history: history,
          exchange_info: { conversation_id: 1, exchange_id: 1 },
          tool_registry: tool_registry,
          application: application_with_debug
        )

        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/file1" } }
          ]
        }

        final_response = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(1)
        allow(tool_registry).to receive(:execute).and_return("file contents")

        orchestrator_with_debug.execute(messages: messages, tools: tools)

        # Should not output detailed batch info (verbosity >= 2 required)
        expect(application_with_debug).not_to have_received(:output_line).with(
          /Batch 1:.*tool.*parallel execution/,
          type: :debug
        )
      end

      it "displays plural text for multiple batches (line 327)" do
        # Test plural form when batch_count > 1
        application_with_debug = instance_double(Nu::Agent::Application,
                                                 formatter: formatter,
                                                 console: console,
                                                 debug: true)
        allow(application_with_debug).to receive(:output_line)

        orchestrator_with_debug = described_class.new(
          client: client,
          history: history,
          exchange_info: { conversation_id: 1, exchange_id: 1 },
          tool_registry: tool_registry,
          application: application_with_debug
        )

        # Configure write tool as barrier to force multiple batches
        allow(tool_registry).to receive(:metadata_for).with("file_write").and_return({
                                                                                       operation_type: :write,
                                                                                       scope: :unconfined
                                                                                     })
        allow(tool_registry).to receive(:metadata_for).with("file_read").and_return({
                                                                                      operation_type: :read,
                                                                                      scope: :confined
                                                                                    })

        tool_call_response = {
          "content" => "",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 10, "output" => 5 },
          "spend" => 0.001,
          "tool_calls" => [
            { "id" => "call_1", "name" => "file_write",
              "arguments" => { "file" => "/file", "content" => "data" } },
            { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "/file" } }
          ]
        }

        final_response = {
          "content" => "Done",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 15, "output" => 8 },
          "spend" => 0.002
        }

        allow(client).to receive(:send_request).and_return(tool_call_response, final_response)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(1)
        allow(tool_registry).to receive(:execute).and_return("result")

        orchestrator_with_debug.execute(messages: messages, tools: tools)

        # Should use plural "batches" because there are 2 batches
        expect(application_with_debug).to have_received(:output_line).with(
          /Created 2 batches from 2 tool calls/,
          type: :debug
        )
      end

      it "formats duration >= 1 second correctly (line 387)" do
        # Test duration formatting when >= 1.0 seconds
        # We need to mock Time.now to control the duration
        application_with_debug = instance_double(Nu::Agent::Application,
                                                 formatter: formatter,
                                                 console: console,
                                                 debug: false)

        orchestrator_with_debug = described_class.new(
          client: client,
          history: history,
          exchange_info: { conversation_id: 1, exchange_id: 1 },
          tool_registry: tool_registry,
          application: application_with_debug
        )

        start_time = Time.now
        end_time = start_time + 1.5 # 1.5 seconds later

        allow(Time).to receive(:now).and_return(start_time, end_time, start_time, end_time)
        allow(client).to receive(:send_request).and_return({
                                                             "content" => "Done",
                                                             "model" => "claude-sonnet-4-5",
                                                             "tokens" => { "input" => 10, "output" => 5 },
                                                             "spend" => 0.001
                                                           })

        # Capture the duration formatting
        allow(application_with_debug).to receive(:respond_to?).with(:debug).and_return(true)
        allow(application_with_debug).to receive(:debug).and_return(true)
        allow(application_with_debug).to receive(:output_line) do |msg, _opts|
          # Check if the message contains the formatted duration >= 1.0s
          expect(msg).to match(/1\.50s/) if msg.include?("API Response")
        end
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(2)

        orchestrator_with_debug.execute(messages: messages, tools: tools)

        # The format_duration method should have been called and formatted as "1.50s"
        expect(client).to have_received(:send_request)
      end
    end
  end
end
