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
      allow(history).to receive(:create_exchange).and_return(exchange_id)
      allow(history).to receive(:add_message)
      allow(formatter).to receive(:display_message_created)

      # Mock conversation history
      allow(history).to receive(:messages).and_return([])

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
end
