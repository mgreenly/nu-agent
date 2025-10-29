# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::ConversationSummarizer do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:summarizer) { instance_double(Nu::Agent::Clients::Anthropic) }
  let(:application) { instance_double(Nu::Agent::Application) }
  let(:status_mutex) { Mutex.new }
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

  describe "#initialize" do
    it "initializes with required dependencies" do
      summarizer_worker = described_class.new(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: summarizer_status, mutex: status_mutex },
        current_conversation_id: 1
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
        current_conversation_id: 1
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
  end

  describe "#summarize_conversations" do
    let(:summarizer_worker) do
      described_class.new(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: summarizer_status, mutex: status_mutex },
        current_conversation_id: 1
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
  end
end
