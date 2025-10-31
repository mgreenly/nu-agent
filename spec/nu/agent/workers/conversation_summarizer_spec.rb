# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Workers::ConversationSummarizer do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:summarizer) { instance_double(Nu::Agent::Clients::Anthropic) }
  let(:application) { instance_double(Nu::Agent::Application, debug: false) }
  let(:status_mutex) { Mutex.new }
  let(:config_store) { instance_double(Nu::Agent::ConfigStore) }
  let(:summarizer_status) do
    {
      "running" => false,
      "total" => 0,
      "completed" => 0,
      "failed" => 0,
      "current_conversation_id" => nil,
      "last_summary" => nil,
      "spend" => 0.0
    }
  end

  let(:summarizer_worker) do
    described_class.new(
      history: history,
      summarizer: summarizer,
      application: application,
      status_info: { status: summarizer_status, mutex: status_mutex },
      current_conversation_id: 1,
      config_store: config_store
    )
  end

  before do
    allow(config_store).to receive(:get_int).with("conversation_summarizer_verbosity", default: 0).and_return(0)
  end

  describe "#initialize" do
    it "initializes with required dependencies" do
      summarizer_worker = described_class.new(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: summarizer_status, mutex: status_mutex },
        current_conversation_id: 1,
        config_store: config_store
      )

      expect(summarizer_worker).to be_a(described_class)
    end
  end

  describe "#start_worker" do
    let(:summarizer_worker) do
      described_class.new(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: summarizer_status, mutex: status_mutex },
        current_conversation_id: 1,
        config_store: config_store
      )
    end

    it "spawns a background thread" do
      # Mock the summarization process to block indefinitely so thread stays alive
      semaphore = Queue.new
      allow(summarizer_worker).to receive(:summarize_conversations) { semaphore.pop }

      thread = summarizer_worker.start_worker

      # Give thread time to start
      sleep(0.01)

      expect(thread).to be_a(Thread)
      expect(thread).to be_alive

      # Clean up
      thread.kill
      thread.join
    end

    it "handles StandardError and sets running to false" do
      # Mock summarize_conversations to raise an error
      allow(summarizer_worker).to receive(:summarize_conversations).and_raise(StandardError.new("Test error"))

      # Start worker and let it crash
      thread = summarizer_worker.start_worker
      sleep(0.05) # Give thread time to crash

      # Verify status was updated
      expect(summarizer_status["running"]).to be false

      thread.join(1) # Clean up
    end
  end

  describe "#summarize_conversations" do
    let(:summarizer_worker) do
      described_class.new(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: summarizer_status, mutex: status_mutex },
        current_conversation_id: 1,
        config_store: config_store
      )
    end

    before do
      # Mock shutdown check
      allow(application).to receive(:instance_variable_get).with(:@shutdown).and_return(false)
    end

    it "returns early when no conversations need summarization" do
      allow(history).to receive(:get_unsummarized_conversations).with(exclude_id: 1).and_return([])

      summarizer_worker.summarize_conversations

      expect(summarizer_status["running"]).to be false
    end

    it "handles empty conversations" do
      conv = { "id" => 2 }
      allow(history).to receive(:get_unsummarized_conversations).with(exclude_id: 1).and_return([conv])
      allow(history).to receive(:messages).with(conversation_id: 2, include_in_context_only: false).and_return([])
      allow(summarizer).to receive(:model).and_return("claude-sonnet-4-5")
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
      allow(history).to receive(:update_conversation_summary)

      summarizer_worker.summarize_conversations

      expect(summarizer_status["completed"]).to eq(1)
      expect(summarizer_status["last_summary"]).to eq("empty conversation")
    end

    it "summarizes conversations with messages" do
      conv = { "id" => 2 }
      messages = [
        { "role" => "user", "content" => "Hello", "redacted" => false },
        { "role" => "assistant", "content" => "Hi there!", "redacted" => false }
      ]
      allow(history).to receive(:get_unsummarized_conversations).with(exclude_id: 1).and_return([conv])
      allow(history).to receive(:messages).with(conversation_id: 2, include_in_context_only: false).and_return(messages)
      allow(summarizer).to receive_messages(model: "claude-sonnet-4-5", send_message: {
                                              "content" => "User greeted the assistant.",
                                              "spend" => 0.001
                                            })
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
      allow(history).to receive(:update_conversation_summary)

      summarizer_worker.summarize_conversations

      expect(summarizer_status["completed"]).to eq(1)
      expect(summarizer_status["last_summary"]).to eq("User greeted the assistant.")
      expect(summarizer_status["spend"]).to eq(0.001)
    end

    it "handles API errors gracefully" do
      conv = { "id" => 2 }
      messages = [{ "role" => "user", "content" => "Hello", "redacted" => false }]
      allow(history).to receive(:get_unsummarized_conversations).with(exclude_id: 1).and_return([conv])
      allow(history).to receive(:messages).with(conversation_id: 2, include_in_context_only: false).and_return(messages)
      allow(summarizer).to receive(:send_message).and_return({ "error" => "API error" })

      summarizer_worker.summarize_conversations

      expect(summarizer_status["failed"]).to eq(1)
      expect(summarizer_status["completed"]).to eq(0)
    end

    it "filters redacted messages" do
      conv = { "id" => 2 }
      messages = [
        { "role" => "user", "content" => "Hello", "redacted" => false },
        { "role" => "assistant", "content" => "Tool call", "redacted" => true },
        { "role" => "assistant", "content" => "Hi there!", "redacted" => false }
      ]
      allow(history).to receive(:get_unsummarized_conversations).with(exclude_id: 1).and_return([conv])
      allow(history).to receive(:messages).with(conversation_id: 2, include_in_context_only: false).and_return(messages)
      allow(summarizer).to receive(:model).and_return("claude-sonnet-4-5")

      # Capture the actual prompt sent to verify redacted messages are filtered
      captured_prompt = nil
      allow(summarizer).to receive(:send_message) do |args|
        captured_prompt = args[:messages].first["content"]
        { "content" => "Summary", "spend" => 0.001 }
      end

      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
      allow(history).to receive(:update_conversation_summary)

      summarizer_worker.summarize_conversations

      # Verify redacted message was not included in prompt
      expect(captured_prompt).to include("user: Hello")
      expect(captured_prompt).to include("assistant: Hi there!")
      expect(captured_prompt).not_to include("Tool call")
    end

    it "handles exceptions during conversation processing" do
      conv = { "id" => 2 }
      allow(history).to receive(:get_unsummarized_conversations).with(exclude_id: 1).and_return([conv])
      allow(history).to receive(:messages).and_raise(StandardError.new("Database error"))
      allow(history).to receive(:create_failed_job)

      summarizer_worker.summarize_conversations

      expect(summarizer_status["failed"]).to eq(1)
    end

    it "handles empty summary response" do
      conv = { "id" => 2 }
      messages = [{ "role" => "user", "content" => "Hello", "redacted" => false }]
      allow(history).to receive(:get_unsummarized_conversations).with(exclude_id: 1).and_return([conv])
      allow(history).to receive(:messages).with(conversation_id: 2, include_in_context_only: false).and_return(messages)
      allow(summarizer).to receive(:send_message).and_return({ "content" => "", "spend" => 0.001 })

      summarizer_worker.summarize_conversations

      expect(summarizer_status["failed"]).to eq(1)
      expect(summarizer_status["completed"]).to eq(0)
    end

    it "handles shutdown during LLM call" do
      conv = { "id" => 2 }
      messages = [{ "role" => "user", "content" => "Hello", "redacted" => false }]
      allow(history).to receive(:get_unsummarized_conversations).with(exclude_id: 1).and_return([conv])
      allow(history).to receive(:messages).with(conversation_id: 2, include_in_context_only: false).and_return(messages)

      # Mock a slow LLM call that takes longer than the shutdown check
      call_count = 0
      allow(application).to receive(:instance_variable_get).with(:@shutdown) do
        call_count += 1
        call_count > 2 # Return false initially, then true to trigger shutdown
      end

      # Mock a slow send_message call
      allow(summarizer).to receive(:send_message) do
        sleep(0.3) # Simulate slow API call
        { "content" => "Summary", "spend" => 0.001 }
      end

      summarizer_worker.summarize_conversations

      # No summary should be saved due to shutdown
      expect(summarizer_status["completed"]).to eq(0)
    end
  end

  describe "#load_verbosity" do
    it "loads verbosity from config store" do
      allow(config_store).to receive(:get_int).with("conversation_summarizer_verbosity", default: 0).and_return(2)
      expect(summarizer_worker.send(:load_verbosity)).to eq(2)
    end
  end

  describe "#debug_output" do
    it "outputs debug messages when debug enabled and within verbosity level" do
      allow(config_store).to receive(:get_int).with("conversation_summarizer_verbosity", default: 0).and_return(1)
      allow(application).to receive(:debug).and_return(true)
      allow(application).to receive(:output_line)

      summarizer_worker.send(:debug_output, "Test message", level: 0)
      expect(application).to have_received(:output_line).with("[ConversationSummarizer] Test message", type: :debug)
    end
  end

  describe "error handling during failure recording" do
    it "handles errors when recording failed job" do
      conv = { "id" => 2 }
      messages = [{ "role" => "user", "content" => "Hello", "redacted" => false }]
      allow(history).to receive(:get_unsummarized_conversations).with(exclude_id: 1).and_return([conv])
      allow(history).to receive(:messages).with(conversation_id: 2, include_in_context_only: false).and_return(messages)
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)

      # Cause summarization to fail
      allow(summarizer).to receive(:send_message).and_raise(StandardError.new("API error"))

      # Cause failure recording to also fail
      allow(history).to receive(:create_failed_job).and_raise(StandardError.new("DB error"))
      allow(application).to receive(:debug).and_return(true)
      allow(application).to receive(:output_line)

      summarizer_worker.summarize_conversations

      expect(summarizer_status["failed"]).to eq(1)
      expect(application).to have_received(:output_line)
        .with(/\[ConversationSummarizer\].*Failed to record failure/, type: :debug)
    end
  end
end
