# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::ChatLoopOrchestrator do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:client) { instance_double(Nu::Agent::Clients::Anthropic, model: "claude-sonnet-4-5") }
  let(:formatter) { instance_double(Nu::Agent::Formatter) }
  let(:tool_registry) { instance_double(Nu::Agent::ToolRegistry) }
  let(:application) do
    instance_double(
      Nu::Agent::Application,
      redact: false,
      spell_check_enabled: false,
      spellchecker: nil
    )
  end
  let(:user_actor) { "testuser" }

  let(:orchestrator) do
    described_class.new(
      history: history,
      formatter: formatter,
      application: application,
      user_actor: user_actor
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

        # The build_context_document should be called with redacted message ranges
        expect(orchestrator).to receive(:build_context_document).with(
          hash_including(redacted_message_ranges: "5-6")
        ).and_call_original

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

    it "builds context document, prepares messages, gets tools, and displays request" do
      # Mock build_context_document to return a specific value
      expect(orchestrator).to receive(:build_context_document).with(
        user_query: user_input,
        tool_registry: tool_registry,
        redacted_message_ranges: redacted_ranges,
        conversation_id: conversation_id
      ).and_return(markdown_doc)

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

      # Verify messages include history + markdown doc
      expect(messages).to eq(history_messages + [{ "role" => "user", "content" => markdown_doc }])

      # Verify tools are formatted
      expect(tools).to eq(formatted_tools)
      expect(client).to have_received(:format_tools).with(tool_registry)

      # Verify display was called
      expect(formatter).to have_received(:display_llm_request).with(messages, formatted_tools, markdown_doc)
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
      it "includes redacted message ranges in RAG content" do
        rag_content = orchestrator.send(
          :build_rag_content,
          user_input,
          "5-6",
          conversation_id
        )

        expect(rag_content).to include("Redacted messages: 5-6")
      end
    end

    context "when spell check is enabled" do
      let(:spellchecker) { instance_double(Nu::Agent::Clients::Anthropic) }
      let(:spell_checker) { instance_double(Nu::Agent::SpellChecker) }

      before do
        allow(application).to receive_messages(spell_check_enabled: true, spellchecker: spellchecker)
        allow(Nu::Agent::SpellChecker).to receive(:new).and_return(spell_checker)
        allow(spell_checker).to receive(:check_spelling).with("teh test").and_return("the test")
      end

      it "includes spell correction in RAG content" do
        rag_content = orchestrator.send(
          :build_rag_content,
          "teh test",
          nil,
          conversation_id
        )

        expect(rag_content).to include("The user said 'teh test' but means 'the test'")
      end
    end

    context "when no RAG content is generated" do
      it "returns default message" do
        rag_content = orchestrator.send(
          :build_rag_content,
          user_input,
          nil,
          conversation_id
        )

        expect(rag_content).to eq(["No Augmented Information Generated"])
      end
    end
  end
end
