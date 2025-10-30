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
      status_mutex: status_mutex,
      embedding_client: nil
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
    it "creates a ConversationSummarizer and ExchangeSummarizer and starts worker threads" do
      mock_conv_thread = instance_double(Thread)
      mock_exch_thread = instance_double(Thread)
      mock_conversation_worker = instance_double(
        Nu::Agent::ConversationSummarizer,
        start_worker: mock_conv_thread
      )
      mock_exchange_worker = instance_double(
        Nu::Agent::ExchangeSummarizer,
        start_worker: mock_exch_thread
      )

      expect(Nu::Agent::ConversationSummarizer).to receive(:new).with(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: worker_manager.summarizer_status, mutex: status_mutex },
        current_conversation_id: conversation_id
      ).and_return(mock_conversation_worker)

      expect(Nu::Agent::ExchangeSummarizer).to receive(:new).with(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: worker_manager.exchange_summarizer_status, mutex: status_mutex },
        current_conversation_id: conversation_id
      ).and_return(mock_exchange_worker)

      worker_manager.start_summarization_worker

      expect(worker_manager.active_threads).to include(mock_conv_thread)
      expect(worker_manager.active_threads).to include(mock_exch_thread)
    end
  end

  describe "thread safety" do
    it "uses operation_mutex for summarization worker" do
      mock_conv_thread = instance_double(Thread)
      mock_exch_thread = instance_double(Thread)
      mock_conversation_worker = instance_double(
        Nu::Agent::ConversationSummarizer,
        start_worker: mock_conv_thread
      )
      mock_exchange_worker = instance_double(
        Nu::Agent::ExchangeSummarizer,
        start_worker: mock_exch_thread
      )

      allow(Nu::Agent::ConversationSummarizer).to receive(:new).and_return(mock_conversation_worker)
      allow(Nu::Agent::ExchangeSummarizer).to receive(:new).and_return(mock_exchange_worker)

      # Start multiple workers concurrently
      threads = 3.times.map do
        Thread.new { worker_manager.start_summarization_worker }
      end

      threads.each(&:join)

      # Should have 6 threads (2 per call: conversation + exchange)
      expect(worker_manager.active_threads.length).to eq(6)
    end
  end
end
