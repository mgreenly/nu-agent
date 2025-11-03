# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::ChatLoopOrchestrator do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:client) { instance_double(Nu::Agent::Clients::Anthropic, model: "claude-sonnet-4-5") }
  let(:formatter) { instance_double(Nu::Agent::Formatter) }
  let(:tool_registry) { instance_double(Nu::Agent::ToolRegistry) }
  let(:event_bus) { instance_double(Nu::Agent::EventBus) }
  let(:application) do
    instance_double(
      Nu::Agent::Application,
      redact: false,
      active_persona_system_prompt: "You are a helpful assistant."
    )
  end
  let(:user_actor) { "testuser" }

  let(:orchestrator) do
    described_class.new(
      history: history,
      formatter: formatter,
      application: application,
      user_actor: user_actor,
      event_bus: event_bus
    )
  end

  let(:conversation_id) { 1 }
  let(:exchange_id) { 123 }
  let(:user_input) { "Hello, how are you?" }
  let(:session_start_time) { Time.now - 3600 }

  describe "#execute" do
    let(:context) do
      {
        session_start_time: session_start_time,
        user_input: user_input,
        application: application
      }
    end

    before do
      # Mock transaction block
      allow(history).to receive(:transaction).and_yield

      # Mock exchange creation
      allow(history).to receive(:add_message)
      allow(formatter).to receive(:display_message_created)

      # Mock conversation history
      allow(history).to receive_messages(create_exchange: exchange_id, messages: [])

      # Mock tool registry
      allow(tool_registry).to receive(:available).and_return([])
      allow(client).to receive(:format_tools).and_return([])

      # Mock formatter methods
      allow(formatter).to receive(:display_llm_request)

      # Mock event bus
      allow(event_bus).to receive(:publish)
    end

    context "when tool_calling_loop succeeds" do
      let(:successful_result) do
        {
          error: false,
          response: {
            "content" => "I'm doing well, thank you!",
            "model" => "claude-sonnet-4-5",
            "tokens" => { "input" => 10, "output" => 15 },
            "spend" => 0.001
          },
          metrics: {
            tokens_input: 10,
            tokens_output: 15,
            spend: 0.001,
            message_count: 1,
            tool_call_count: 0
          }
        }
      end

      it "includes system prompt in LLM request" do
        allow(history).to receive(:complete_exchange)
        allow(orchestrator).to receive(:tool_calling_loop).and_return(successful_result)

        # Capture the internal_format passed to display_llm_request
        expect(formatter).to receive(:display_llm_request) do |internal_format|
          expect(internal_format[:system_prompt]).to eq("You are a helpful assistant.")
        end

        orchestrator.execute(
          conversation_id: conversation_id,
          client: client,
          tool_registry: tool_registry,
          **context
        )
      end

      it "creates exchange, executes chat loop, and completes successfully" do
        allow(history).to receive(:complete_exchange)

        # Mock the tool_calling_loop call
        expect(orchestrator).to receive(:tool_calling_loop).and_return(successful_result)

        orchestrator.execute(
          conversation_id: conversation_id,
          client: client,
          tool_registry: tool_registry,
          **context
        )

        # Verify exchange was created
        expect(history).to have_received(:create_exchange).with(
          conversation_id: conversation_id,
          user_message: user_input
        )

        # Verify user message was added
        expect(history).to have_received(:add_message).with(
          hash_including(
            conversation_id: conversation_id,
            exchange_id: exchange_id,
            actor: user_actor,
            role: "user",
            content: user_input
          )
        )

        # Verify assistant response was added
        expect(history).to have_received(:add_message).with(
          hash_including(
            conversation_id: conversation_id,
            exchange_id: exchange_id,
            actor: "orchestrator",
            role: "assistant",
            content: "I'm doing well, thank you!",
            redacted: false
          )
        )

        # Verify exchange was completed
        # Note: metrics are accumulated - final response adds to existing metrics
        expect(history).to have_received(:complete_exchange).with(
          exchange_id: exchange_id,
          assistant_message: "I'm doing well, thank you!",
          metrics: hash_including(
            tokens_input: 10,
            tokens_output: 30, # 15 + 15 (accumulated)
            spend: 0.002,      # 0.001 + 0.001 (accumulated)
            message_count: 2   # 1 + 1 (accumulated)
          )
        )
      end
    end

    context "when tool_calling_loop returns an error" do
      let(:error_result) do
        {
          error: true,
          response: {
            "error" => "API Error",
            "content" => "Something went wrong"
          },
          metrics: {
            tokens_input: 5,
            tokens_output: 0,
            spend: 0.0,
            message_count: 1,
            tool_call_count: 0
          }
        }
      end

      it "marks exchange as failed" do
        allow(history).to receive(:update_exchange)

        # Mock the tool_calling_loop call
        expect(orchestrator).to receive(:tool_calling_loop).and_return(error_result)

        orchestrator.execute(
          conversation_id: conversation_id,
          client: client,
          tool_registry: tool_registry,
          **context
        )

        # Verify exchange was marked as failed
        expect(history).to have_received(:update_exchange).with(
          hash_including(
            exchange_id: exchange_id,
            updates: hash_including(
              status: "failed"
            )
          )
        )
      end
    end

    context "when redaction is enabled" do
      before do
        allow(application).to receive(:redact).and_return(true)

        # Mock messages with some redacted
        redacted_messages = [
          { "id" => 5, "redacted" => true, "exchange_id" => 100 },
          { "id" => 6, "redacted" => true, "exchange_id" => 100 },
          { "id" => 8, "redacted" => false, "exchange_id" => 100 }
        ]
        allow(history).to receive(:messages).and_return(redacted_messages)
      end

      it "formats redacted message ranges" do
        successful_result = {
          error: false,
          response: {
            "content" => "Response",
            "model" => "claude-sonnet-4-5",
            "tokens" => { "input" => 10, "output" => 15 },
            "spend" => 0.001
          },
          metrics: {
            tokens_input: 10,
            tokens_output: 15,
            spend: 0.001,
            message_count: 1,
            tool_call_count: 0
          }
        }

        allow(history).to receive(:complete_exchange)
        allow(orchestrator).to receive(:tool_calling_loop).and_return(successful_result)

        # NOTE: RAG content with redacted ranges is now built separately
        # and merged by LlmRequestBuilder
        orchestrator.execute(
          conversation_id: conversation_id,
          client: client,
          tool_registry: tool_registry,
          **context
        )
      end
    end
  end

  describe "#create_user_message" do
    it "creates exchange, adds user message, and returns exchange_id" do
      allow(history).to receive(:create_exchange).and_return(exchange_id)
      allow(history).to receive(:add_message)
      allow(formatter).to receive(:display_message_created)
      allow(event_bus).to receive(:publish)

      result = orchestrator.send(:create_user_message, conversation_id, user_input)

      expect(result).to eq(exchange_id)

      expect(history).to have_received(:create_exchange).with(
        conversation_id: conversation_id,
        user_message: user_input
      )

      expect(history).to have_received(:add_message).with(
        conversation_id: conversation_id,
        exchange_id: exchange_id,
        actor: user_actor,
        role: "user",
        content: user_input
      )

      expect(formatter).to have_received(:display_message_created).with(
        actor: user_actor,
        role: "user",
        content: user_input
      )
    end
  end

  describe "#prepare_history_messages" do
    context "when redaction is disabled" do
      it "returns filtered messages and nil redacted ranges" do
        messages = [
          { "id" => 1, "redacted" => false, "exchange_id" => 100 },
          { "id" => 2, "redacted" => false, "exchange_id" => 100 },
          { "id" => 3, "redacted" => false, "exchange_id" => exchange_id }
        ]
        allow(history).to receive(:messages).and_return(messages)
        allow(application).to receive(:redact).and_return(false)

        history_msgs, redacted_ranges = orchestrator.send(
          :prepare_history_messages,
          conversation_id,
          exchange_id,
          session_start_time
        )

        expect(history_msgs).to eq([
                                     { "id" => 1, "redacted" => false, "exchange_id" => 100 },
                                     { "id" => 2, "redacted" => false, "exchange_id" => 100 }
                                   ])
        expect(redacted_ranges).to be_nil
      end
    end

    context "when redaction is enabled" do
      it "returns filtered messages and formatted redacted ranges" do
        messages = [
          { "id" => 5, "redacted" => true, "exchange_id" => 100 },
          { "id" => 6, "redacted" => true, "exchange_id" => 100 },
          { "id" => 7, "redacted" => false, "exchange_id" => 101 },
          { "id" => 8, "redacted" => false, "exchange_id" => exchange_id }
        ]
        allow(history).to receive(:messages).and_return(messages)
        allow(application).to receive(:redact).and_return(true)

        history_msgs, redacted_ranges = orchestrator.send(
          :prepare_history_messages,
          conversation_id,
          exchange_id,
          session_start_time
        )

        expect(history_msgs).to eq([
                                     { "id" => 7, "redacted" => false, "exchange_id" => 101 }
                                   ])
        expect(redacted_ranges).to eq("5-6")
      end

      it "returns nil redacted ranges when no messages are redacted" do
        messages = [
          { "id" => 7, "redacted" => false, "exchange_id" => 101 },
          { "id" => 8, "redacted" => false, "exchange_id" => exchange_id }
        ]
        allow(history).to receive(:messages).and_return(messages)
        allow(application).to receive(:redact).and_return(true)

        history_msgs, redacted_ranges = orchestrator.send(
          :prepare_history_messages,
          conversation_id,
          exchange_id,
          session_start_time
        )

        expect(history_msgs).to eq([
                                     { "id" => 7, "redacted" => false, "exchange_id" => 101 }
                                   ])
        expect(redacted_ranges).to be_nil
      end
    end
  end

  describe "#prepare_llm_request" do
    let(:history_messages) do
      [
        { "role" => "user", "content" => "Previous message" },
        { "role" => "assistant", "content" => "Previous response" }
      ]
    end
    let(:redacted_ranges) { "5-6" }
    let(:formatted_tools) { [{ "name" => "test_tool" }] }
    let(:markdown_doc) { "# Context\n\nUser Query: #{user_input}" }

    before do
      allow(tool_registry).to receive(:available).and_return([])
      allow(client).to receive(:format_tools).and_return(formatted_tools)
      allow(formatter).to receive(:display_llm_request)
    end

    it "uses LlmRequestBuilder to construct request" do
      # Mock build_rag_content - note that builder now merges RAG with user_query internally
      rag_content = { redactions: redacted_ranges }
      expect(orchestrator).to receive(:build_rag_content).with(
        user_input,
        redacted_ranges,
        conversation_id
      ).and_return(rag_content)

      # Expect builder to be created and used
      builder = instance_double(Nu::Agent::LlmRequestBuilder)
      expect(Nu::Agent::LlmRequestBuilder).to receive(:new).and_return(builder)

      expect(builder).to receive(:with_system_prompt).with("You are a helpful assistant.").and_return(builder)
      expect(builder).to receive(:with_history).with(history_messages).and_return(builder)
      expect(builder).to receive(:with_rag_content).with(rag_content).and_return(builder)
      # Now passes raw user_input instead of merged markdown_doc
      expect(builder).to receive(:with_user_query).with(user_input).and_return(builder)
      expect(builder).to receive(:with_tools).with(formatted_tools).and_return(builder)
      expect(builder).to receive(:with_metadata)
        .with(hash_including(conversation_id: conversation_id))
        .and_return(builder)

      # Mock build to return internal format
      internal_format = {
        messages: history_messages + [{ "role" => "user", "content" => markdown_doc }],
        tools: formatted_tools
      }
      expect(builder).to receive(:build).and_return(internal_format)

      request_context = {
        user_query: user_input,
        history_messages: history_messages,
        redacted_ranges: redacted_ranges
      }

      messages, tools = orchestrator.send(
        :prepare_llm_request,
        request_context,
        tool_registry,
        conversation_id,
        client
      )

      # Verify messages and tools are extracted from builder's output
      expect(messages).to eq(history_messages + [{ "role" => "user", "content" => markdown_doc }])
      expect(tools).to eq(formatted_tools)

      # Verify display was called with internal format
      expect(formatter).to have_received(:display_llm_request).with(internal_format)
    end

    it "uses nil system prompt when application does not respond to active_persona_system_prompt" do
      application_without_persona = instance_double(Nu::Agent::Application, redact: false)
      orchestrator_without_persona = described_class.new(
        history: history,
        formatter: formatter,
        application: application_without_persona,
        user_actor: user_actor,
        event_bus: event_bus
      )

      rag_content = {}
      expect(orchestrator_without_persona).to receive(:build_rag_content).and_return(rag_content)

      builder = instance_double(Nu::Agent::LlmRequestBuilder)
      expect(Nu::Agent::LlmRequestBuilder).to receive(:new).and_return(builder)

      expect(builder).to receive(:with_system_prompt).with(nil).and_return(builder)
      expect(builder).to receive(:with_history).with(history_messages).and_return(builder)
      expect(builder).to receive(:with_rag_content).with(rag_content).and_return(builder)
      expect(builder).to receive(:with_user_query).with(user_input).and_return(builder)
      expect(builder).to receive(:with_tools).with(formatted_tools).and_return(builder)
      expect(builder).to receive(:with_metadata)
        .with(hash_including(conversation_id: conversation_id))
        .and_return(builder)

      internal_format = {
        messages: history_messages + [{ "role" => "user", "content" => user_input }],
        tools: formatted_tools
      }
      expect(builder).to receive(:build).and_return(internal_format)

      request_context = {
        user_query: user_input,
        history_messages: history_messages,
        redacted_ranges: nil
      }

      orchestrator_without_persona.send(
        :prepare_llm_request,
        request_context,
        tool_registry,
        conversation_id,
        client
      )

      expect(formatter).to have_received(:display_llm_request).with(internal_format)
    end
  end

  describe "#handle_error_result" do
    let(:error_result) do
      {
        error: true,
        response: {
          "error" => "API Error message",
          "content" => "Error occurred"
        },
        metrics: {
          tokens_input: 10,
          tokens_output: 0,
          spend: 0.0,
          message_count: 1,
          tool_call_count: 0
        }
      }
    end

    it "updates exchange as failed with error and metrics" do
      allow(history).to receive(:update_exchange)

      orchestrator.send(:handle_error_result, exchange_id, error_result)

      expect(history).to have_received(:update_exchange).with(
        exchange_id: exchange_id,
        updates: hash_including(
          status: "failed",
          error: '"API Error message"',
          tokens_input: 10,
          tokens_output: 0,
          spend: 0.0,
          message_count: 1,
          tool_call_count: 0
        )
      )
    end
  end

  describe "#handle_success_result" do
    let(:success_result) do
      {
        error: false,
        response: {
          "content" => "Final response",
          "model" => "claude-sonnet-4-5",
          "tokens" => { "input" => 20, "output" => 30 },
          "spend" => 0.005
        },
        metrics: {
          tokens_input: 10,
          tokens_output: 15,
          spend: 0.002,
          message_count: 1,
          tool_call_count: 2
        }
      }
    end

    it "adds final message and completes exchange with accumulated metrics" do
      allow(history).to receive(:add_message)
      allow(history).to receive(:complete_exchange)
      allow(formatter).to receive(:display_message_created)
      allow(event_bus).to receive(:publish)

      orchestrator.send(:handle_success_result, conversation_id, exchange_id, success_result)

      # Verify final message was added
      expect(history).to have_received(:add_message).with(
        conversation_id: conversation_id,
        exchange_id: exchange_id,
        actor: "orchestrator",
        role: "assistant",
        content: "Final response",
        model: "claude-sonnet-4-5",
        tokens_input: 20,
        tokens_output: 30,
        spend: 0.005,
        redacted: false
      )

      # Verify display was called
      expect(formatter).to have_received(:display_message_created).with(
        actor: "orchestrator",
        role: "assistant",
        content: "Final response",
        redacted: false
      )

      # Verify exchange was completed with accumulated metrics
      expect(history).to have_received(:complete_exchange).with(
        exchange_id: exchange_id,
        assistant_message: "Final response",
        metrics: hash_including(
          tokens_input: 20,      # max(10, 20)
          tokens_output: 45,     # 15 + 30
          spend: 0.007,          # 0.002 + 0.005
          message_count: 2,      # 1 + 1
          tool_call_count: 2
        )
      )
    end
  end

  describe "#save_final_response" do
    let(:final_response) do
      {
        "content" => "Test response",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 15, "output" => 25 },
        "spend" => 0.003
      }
    end

    it "saves final message to history and displays it" do
      allow(history).to receive(:add_message)
      allow(formatter).to receive(:display_message_created)

      orchestrator.send(:save_final_response, conversation_id, exchange_id, final_response)

      expect(history).to have_received(:add_message).with(
        conversation_id: conversation_id,
        exchange_id: exchange_id,
        actor: "orchestrator",
        role: "assistant",
        content: "Test response",
        model: "claude-sonnet-4-5",
        tokens_input: 15,
        tokens_output: 25,
        spend: 0.003,
        redacted: false
      )

      expect(formatter).to have_received(:display_message_created).with(
        actor: "orchestrator",
        role: "assistant",
        content: "Test response",
        redacted: false
      )
    end
  end

  describe "#accumulate_final_metrics" do
    it "accumulates metrics from final response into existing metrics" do
      metrics = {
        tokens_input: 10,
        tokens_output: 15,
        spend: 0.002,
        message_count: 1,
        tool_call_count: 2
      }

      final_response = {
        "tokens" => { "input" => 20, "output" => 30 },
        "spend" => 0.005
      }

      result = orchestrator.send(:accumulate_final_metrics, metrics, final_response)

      expect(result).to eq({
                             tokens_input: 20, # max(10, 20)
                             tokens_output: 45,     # 15 + 30
                             spend: 0.007,          # 0.002 + 0.005
                             message_count: 2,      # 1 + 1
                             tool_call_count: 2     # unchanged
                           })
    end

    it "handles nil token values gracefully" do
      metrics = {
        tokens_input: 10,
        tokens_output: 15,
        spend: 0.002,
        message_count: 1
      }

      final_response = {
        "tokens" => {},
        "spend" => nil
      }

      result = orchestrator.send(:accumulate_final_metrics, metrics, final_response)

      expect(result).to eq({
                             tokens_input: 10, # max(10, 0)
                             tokens_output: 15,     # 15 + 0
                             spend: 0.002,          # 0.002 + 0.0
                             message_count: 2       # 1 + 1
                           })
    end
  end

  describe "#build_rag_content" do
    context "when redaction is enabled" do
      it "includes redacted message ranges in structured RAG content" do
        rag_content = orchestrator.send(
          :build_rag_content,
          user_input,
          "5-6",
          conversation_id
        )

        expect(rag_content).to be_a(Hash)
        expect(rag_content[:redactions]).to eq("5-6")
      end
    end

    context "when no RAG content is generated" do
      it "returns empty hash" do
        rag_content = orchestrator.send(
          :build_rag_content,
          user_input,
          nil,
          conversation_id
        )

        expect(rag_content).to eq({})
      end
    end
  end

  describe "#tool_calling_loop" do
    let(:messages) { [{ "role" => "user", "content" => "test" }] }
    let(:tools) { [{ "name" => "test_tool" }] }
    let(:tool_call_orchestrator) { instance_double(Nu::Agent::ToolCallOrchestrator) }
    let(:loop_result) do
      {
        error: false,
        response: { "content" => "result" },
        metrics: { tokens_input: 10 }
      }
    end

    it "creates ToolCallOrchestrator and executes with context parameters" do
      allow(Nu::Agent::ToolCallOrchestrator).to receive(:new).and_return(tool_call_orchestrator)
      allow(tool_call_orchestrator).to receive(:execute).and_return(loop_result)

      result = orchestrator.send(
        :tool_calling_loop,
        messages: messages,
        client: client,
        conversation_id: conversation_id,
        tools: tools,
        history: history,
        exchange_id: exchange_id,
        tool_registry: tool_registry,
        application: application
      )

      expect(Nu::Agent::ToolCallOrchestrator).to have_received(:new).with(
        client: client,
        history: history,
        exchange_info: { conversation_id: conversation_id, exchange_id: exchange_id },
        tool_registry: tool_registry,
        application: application
      )

      expect(tool_call_orchestrator).to have_received(:execute).with(
        messages: messages,
        tools: tools,
        system_prompt: "You are a helpful assistant."
      )

      expect(result).to eq(loop_result)
    end

    it "passes active persona system prompt when available" do
      allow(Nu::Agent::ToolCallOrchestrator).to receive(:new).and_return(tool_call_orchestrator)
      allow(tool_call_orchestrator).to receive(:execute).and_return(loop_result)
      allow(application).to receive(:respond_to?).with(:active_persona_system_prompt).and_return(true)
      allow(application).to receive(:active_persona_system_prompt).and_return("Custom persona prompt")

      result = orchestrator.send(
        :tool_calling_loop,
        messages: messages,
        client: client,
        conversation_id: conversation_id,
        tools: tools,
        history: history,
        exchange_id: exchange_id,
        tool_registry: tool_registry,
        application: application
      )

      expect(tool_call_orchestrator).to have_received(:execute).with(
        messages: messages,
        tools: tools,
        system_prompt: "Custom persona prompt"
      )

      expect(result).to eq(loop_result)
    end

    it "passes nil system prompt when application does not respond to active_persona_system_prompt" do
      application_without_persona = instance_double(Nu::Agent::Application, redact: false)
      orchestrator_without_persona = described_class.new(
        history: history,
        formatter: formatter,
        application: application_without_persona,
        user_actor: user_actor,
        event_bus: event_bus
      )

      allow(Nu::Agent::ToolCallOrchestrator).to receive(:new).and_return(tool_call_orchestrator)
      allow(tool_call_orchestrator).to receive(:execute).and_return(loop_result)

      result = orchestrator_without_persona.send(
        :tool_calling_loop,
        messages: messages,
        client: client,
        conversation_id: conversation_id,
        tools: tools,
        history: history,
        exchange_id: exchange_id,
        tool_registry: tool_registry,
        application: application_without_persona
      )

      expect(tool_call_orchestrator).to have_received(:execute).with(
        messages: messages,
        tools: tools,
        system_prompt: nil
      )

      expect(result).to eq(loop_result)
    end
  end

  describe "#format_id_ranges" do
    it "formats consecutive IDs as ranges" do
      result = orchestrator.send(:format_id_ranges, [5, 6, 7])
      expect(result).to eq("5-7")
    end

    it "formats non-consecutive IDs with multiple ranges" do
      result = orchestrator.send(:format_id_ranges, [5, 6, 10, 11, 15])
      expect(result).to eq("5-6, 10-11, 15")
    end

    it "formats single ID without range notation" do
      result = orchestrator.send(:format_id_ranges, [5])
      expect(result).to eq("5")
    end

    it "returns empty string for empty array" do
      result = orchestrator.send(:format_id_ranges, [])
      expect(result).to eq("")
    end

    it "handles all non-consecutive IDs" do
      result = orchestrator.send(:format_id_ranges, [1, 3, 5, 7])
      expect(result).to eq("1, 3, 5, 7")
    end
  end
end
