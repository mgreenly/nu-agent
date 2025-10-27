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

    it "initializes man_indexer status with default values" do
      status = worker_manager.man_indexer_status

      expect(status["running"]).to be false
      expect(status["total"]).to eq(0)
      expect(status["completed"]).to eq(0)
      expect(status["failed"]).to eq(0)
      expect(status["skipped"]).to eq(0)
      expect(status["current_batch"]).to be_nil
      expect(status["session_spend"]).to eq(0.0)
      expect(status["session_tokens"]).to eq(0)
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

  describe "#start_man_indexer_worker" do
    context "when OpenAI embeddings client can be created" do
      it "creates a ManPageIndexer and starts worker thread" do
        mock_thread = instance_double(Thread)
        mock_embeddings_client = instance_double(Nu::Agent::Clients::OpenAIEmbeddings)
        mock_indexer = instance_double(
          Nu::Agent::ManPageIndexer,
          start_worker: mock_thread
        )

        expect(Nu::Agent::Clients::OpenAIEmbeddings).to receive(:new).and_return(mock_embeddings_client)

        expect(Nu::Agent::ManPageIndexer).to receive(:new).with(
          history: history,
          embeddings_client: mock_embeddings_client,
          application: application,
          status: worker_manager.man_indexer_status,
          status_mutex: status_mutex
        ).and_return(mock_indexer)

        worker_manager.start_man_indexer_worker

        expect(worker_manager.active_threads).to include(mock_thread)
      end
    end

    context "when OpenAI embeddings client creation fails" do
      it "displays error message and sets status to not running" do
        allow(Nu::Agent::Clients::OpenAIEmbeddings).to receive(:new).and_raise(
          StandardError.new("API key missing")
        )

        expect(application).to receive(:output_line).with(
          "[Man Indexer] ERROR: Failed to create OpenAI Embeddings client",
          type: :error
        )
        expect(application).to receive(:output_line).with("  API key missing", type: :error)
        expect(application).to receive(:output_line).with(
          "Man page indexing requires OpenAI embeddings API access.",
          type: :error
        )
        expect(application).to receive(:output_line).with(
          "Please ensure your OpenAI API key has access to text-embedding-3-small.",
          type: :error
        )

        worker_manager.start_man_indexer_worker

        expect(worker_manager.man_indexer_status["running"]).to be false
        expect(worker_manager.active_threads).to be_empty
      end
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
