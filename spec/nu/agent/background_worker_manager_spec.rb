# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::BackgroundWorkerManager do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:application) { instance_double(Nu::Agent::Application, output_line: nil) }
  let(:summarizer) { instance_double("Summarizer") }
  let(:conversation_id) { 1 }
  let(:status_mutex) { Mutex.new }

  let(:worker_manager) do
    described_class.new(
      application: application,
      history: history,
      summarizer: summarizer,
      conversation_id: conversation_id,
      status_mutex: status_mutex
    )
  end

  describe "#initialize" do
    it "initializes summarizer status with default values" do
      status = worker_manager.summarizer_status

      expect(status["running"]).to be false
      expect(status["total"]).to eq(0)
      expect(status["completed"]).to eq(0)
      expect(status["failed"]).to eq(0)
      expect(status["current_conversation_id"]).to be_nil
      expect(status["last_summary"]).to be_nil
      expect(status["spend"]).to eq(0.0)
    end

    it "initializes active_threads as empty array" do
      expect(worker_manager.active_threads).to eq([])
    end
  end

  describe "#start_summarization_worker" do
    it "creates a ConversationSummarizer and starts worker thread" do
      mock_thread = instance_double(Thread)
      mock_summarizer_worker = instance_double(
        Nu::Agent::ConversationSummarizer,
        start_worker: mock_thread
      )

      expect(Nu::Agent::ConversationSummarizer).to receive(:new).with(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: worker_manager.summarizer_status, mutex: status_mutex },
        current_conversation_id: conversation_id
      ).and_return(mock_summarizer_worker)

      worker_manager.start_summarization_worker

      expect(worker_manager.active_threads).to include(mock_thread)
    end
  end

  describe "thread safety" do
    it "uses operation_mutex for summarization worker" do
      mock_thread = instance_double(Thread)
      mock_summarizer_worker = instance_double(
        Nu::Agent::ConversationSummarizer,
        start_worker: mock_thread
      )

      allow(Nu::Agent::ConversationSummarizer).to receive(:new).and_return(mock_summarizer_worker)

      # Start multiple workers concurrently
      threads = 3.times.map do
        Thread.new { worker_manager.start_summarization_worker }
      end

      threads.each(&:join)

      # Should have 3 threads (one per call)
      expect(worker_manager.active_threads.length).to eq(3)
    end
  end
end
