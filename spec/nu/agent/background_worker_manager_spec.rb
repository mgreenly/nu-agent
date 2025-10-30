# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::BackgroundWorkerManager do
  let(:config_store) { instance_double(Nu::Agent::ConfigStore) }
  let(:history) { instance_double(Nu::Agent::History) }
  let(:application) { instance_double(Nu::Agent::Application, output_line: nil) }
  let(:summarizer) { instance_double("Summarizer") }
  let(:conversation_id) { 1 }
  let(:status_mutex) { Mutex.new }

  before do
    allow(history).to receive(:instance_variable_get).with(:@config_store).and_return(config_store)
  end

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
        Nu::Agent::Workers::ConversationSummarizer,
        start_worker: mock_conv_thread
      )
      mock_exchange_worker = instance_double(
        Nu::Agent::Workers::ExchangeSummarizer,
        start_worker: mock_exch_thread
      )

      expect(Nu::Agent::Workers::ConversationSummarizer).to receive(:new).with(
        history: history,
        summarizer: summarizer,
        application: application,
        status_info: { status: worker_manager.summarizer_status, mutex: status_mutex },
        current_conversation_id: conversation_id,
        config_store: config_store
      ).and_return(mock_conversation_worker)

      expect(Nu::Agent::Workers::ExchangeSummarizer).to receive(:new).with(
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
        Nu::Agent::Workers::ConversationSummarizer,
        start_worker: mock_conv_thread
      )
      mock_exchange_worker = instance_double(
        Nu::Agent::Workers::ExchangeSummarizer,
        start_worker: mock_exch_thread
      )

      allow(Nu::Agent::Workers::ConversationSummarizer).to receive(:new).and_return(mock_conversation_worker)
      allow(Nu::Agent::Workers::ExchangeSummarizer).to receive(:new).and_return(mock_exchange_worker)

      # Start multiple workers concurrently
      threads = 3.times.map do
        Thread.new { worker_manager.start_summarization_worker }
      end

      threads.each(&:join)

      # Should have 6 threads (2 per call: conversation + exchange)
      expect(worker_manager.active_threads.length).to eq(6)
    end
  end

  describe "#start_worker" do
    context "with conversation-summarizer" do
      it "starts the conversation summarizer worker" do
        mock_thread = instance_double(Thread)
        mock_worker = instance_double(
          Nu::Agent::Workers::ConversationSummarizer,
          start_worker: mock_thread
        )

        expect(Nu::Agent::Workers::ConversationSummarizer).to receive(:new).and_return(mock_worker)
        expect(Nu::Agent::Workers::ExchangeSummarizer).not_to receive(:new)

        result = worker_manager.start_worker("conversation-summarizer")
        expect(result).to be true
        expect(worker_manager.active_threads).to include(mock_thread)
      end
    end

    context "with exchange-summarizer" do
      it "starts the exchange summarizer worker" do
        mock_thread = instance_double(Thread)
        mock_worker = instance_double(
          Nu::Agent::Workers::ExchangeSummarizer,
          start_worker: mock_thread
        )

        expect(Nu::Agent::Workers::ExchangeSummarizer).to receive(:new).and_return(mock_worker)
        expect(Nu::Agent::Workers::ConversationSummarizer).not_to receive(:new)

        result = worker_manager.start_worker("exchange-summarizer")
        expect(result).to be true
        expect(worker_manager.active_threads).to include(mock_thread)
      end
    end

    context "with embeddings" do
      let(:embedding_client) { instance_double("EmbeddingClient") }
      let(:config_store) { instance_double(Nu::Agent::ConfigStore) }
      let(:worker_manager) do
        described_class.new(
          application: application,
          history: history,
          summarizer: summarizer,
          conversation_id: conversation_id,
          status_mutex: status_mutex,
          embedding_client: embedding_client
        )
      end

      it "starts the embedding generator worker" do
        mock_thread = instance_double(Thread)
        mock_worker = instance_double(
          Nu::Agent::Workers::EmbeddingGenerator,
          start_worker: mock_thread
        )

        allow(history).to receive(:instance_variable_get).with(:@config_store).and_return(config_store)
        expect(Nu::Agent::Workers::EmbeddingGenerator).to receive(:new).and_return(mock_worker)

        result = worker_manager.start_worker("embeddings")
        expect(result).to be true
        expect(worker_manager.active_threads).to include(mock_thread)
      end

      it "returns false when embedding_client is nil" do
        worker_manager_no_client = described_class.new(
          application: application,
          history: history,
          summarizer: summarizer,
          conversation_id: conversation_id,
          status_mutex: status_mutex,
          embedding_client: nil
        )

        result = worker_manager_no_client.start_worker("embeddings")
        expect(result).to be false
      end
    end

    context "with invalid worker name" do
      it "returns false" do
        result = worker_manager.start_worker("invalid-worker")
        expect(result).to be false
      end
    end

    context "when worker is already running" do
      it "does not start duplicate worker" do
        mock_thread = instance_double(Thread, alive?: true)
        mock_worker = instance_double(
          Nu::Agent::Workers::ConversationSummarizer,
          start_worker: mock_thread
        )

        allow(Nu::Agent::Workers::ConversationSummarizer).to receive(:new).and_return(mock_worker)

        # Start first time
        worker_manager.start_worker("conversation-summarizer")
        expect(worker_manager.active_threads.length).to eq(1)

        # Try to start again - should not create duplicate
        result = worker_manager.start_worker("conversation-summarizer")
        expect(result).to be false
        expect(worker_manager.active_threads.length).to eq(1)
      end
    end
  end

  describe "#stop_worker" do
    before do
      # Mock Thread.kill to prevent actual thread killing in tests
      allow(Thread).to receive(:kill)
    end

    it "stops a running worker by name" do
      mock_thread = instance_double(Thread, alive?: true)
      mock_worker = instance_double(
        Nu::Agent::Workers::ConversationSummarizer,
        start_worker: mock_thread
      )

      allow(Nu::Agent::Workers::ConversationSummarizer).to receive(:new).and_return(mock_worker)

      # Start the worker
      worker_manager.start_worker("conversation-summarizer")

      # Stop it
      expect(Thread).to receive(:kill).with(mock_thread)
      result = worker_manager.stop_worker("conversation-summarizer")
      expect(result).to be true
    end

    it "returns false for invalid worker name" do
      result = worker_manager.stop_worker("invalid-worker")
      expect(result).to be false
    end

    it "returns false when worker is not running" do
      result = worker_manager.stop_worker("conversation-summarizer")
      expect(result).to be false
    end
  end

  describe "#worker_status" do
    it "returns status for conversation-summarizer" do
      status = worker_manager.worker_status("conversation-summarizer")
      expect(status).to eq(worker_manager.summarizer_status)
    end

    it "returns status for exchange-summarizer" do
      status = worker_manager.worker_status("exchange-summarizer")
      expect(status).to eq(worker_manager.exchange_summarizer_status)
    end

    it "returns status for embeddings" do
      status = worker_manager.worker_status("embeddings")
      expect(status).to eq(worker_manager.embedding_status)
    end

    it "returns nil for invalid worker name" do
      status = worker_manager.worker_status("invalid-worker")
      expect(status).to be_nil
    end
  end

  describe "#all_workers_status" do
    it "returns hash with all worker statuses" do
      statuses = worker_manager.all_workers_status

      expect(statuses).to be_a(Hash)
      expect(statuses["conversation-summarizer"]).to eq(worker_manager.summarizer_status)
      expect(statuses["exchange-summarizer"]).to eq(worker_manager.exchange_summarizer_status)
      expect(statuses["embeddings"]).to eq(worker_manager.embedding_status)
    end
  end

  describe "#worker_enabled?" do
    let(:config_store) { instance_double(Nu::Agent::ConfigStore) }

    before do
      allow(history).to receive(:instance_variable_get).with(:@config_store).and_return(config_store)
    end

    it "returns true when conversation_summarizer_enabled is true" do
      allow(config_store).to receive(:get_config).with("conversation_summarizer_enabled").and_return("true")
      expect(worker_manager.worker_enabled?("conversation-summarizer")).to be true
    end

    it "returns false when conversation_summarizer_enabled is false" do
      allow(config_store).to receive(:get_config).with("conversation_summarizer_enabled").and_return("false")
      expect(worker_manager.worker_enabled?("conversation-summarizer")).to be false
    end

    it "returns true by default when config not set (conversation-summarizer)" do
      allow(config_store).to receive(:get_config).with("conversation_summarizer_enabled").and_return(nil)
      expect(worker_manager.worker_enabled?("conversation-summarizer")).to be true
    end

    it "returns true by default when config not set (exchange-summarizer)" do
      allow(config_store).to receive(:get_config).with("exchange_summarizer_enabled").and_return(nil)
      expect(worker_manager.worker_enabled?("exchange-summarizer")).to be true
    end

    it "returns false by default when config not set (embeddings)" do
      allow(config_store).to receive(:get_config).with("embeddings_enabled").and_return(nil)
      expect(worker_manager.worker_enabled?("embeddings")).to be false
    end

    it "returns false for invalid worker name" do
      expect(worker_manager.worker_enabled?("invalid-worker")).to be false
    end
  end

  describe "#enable_worker" do
    let(:config_store) { instance_double(Nu::Agent::ConfigStore) }

    before do
      allow(history).to receive(:instance_variable_get).with(:@config_store).and_return(config_store)
      allow(config_store).to receive(:set_config)
    end

    it "enables and starts conversation-summarizer" do
      mock_thread = instance_double(Thread)
      mock_worker = instance_double(
        Nu::Agent::Workers::ConversationSummarizer,
        start_worker: mock_thread
      )

      allow(Nu::Agent::Workers::ConversationSummarizer).to receive(:new).and_return(mock_worker)

      expect(config_store).to receive(:set_config).with("conversation_summarizer_enabled", "true")
      result = worker_manager.enable_worker("conversation-summarizer")

      expect(result).to be true
      expect(worker_manager.active_threads).to include(mock_thread)
    end

    it "returns false for invalid worker name" do
      result = worker_manager.enable_worker("invalid-worker")
      expect(result).to be false
    end

    it "does not start worker if already running" do
      mock_thread = instance_double(Thread, alive?: true)
      mock_worker = instance_double(
        Nu::Agent::Workers::ConversationSummarizer,
        start_worker: mock_thread
      )

      allow(Nu::Agent::Workers::ConversationSummarizer).to receive(:new).and_return(mock_worker)

      # Start first
      worker_manager.start_worker("conversation-summarizer")

      # Enable (should just set config, not start duplicate)
      expect(config_store).to receive(:set_config).with("conversation_summarizer_enabled", "true")
      result = worker_manager.enable_worker("conversation-summarizer")

      expect(result).to be true
      expect(worker_manager.active_threads.length).to eq(1)
    end
  end

  describe "#disable_worker" do
    let(:config_store) { instance_double(Nu::Agent::ConfigStore) }

    before do
      allow(history).to receive(:instance_variable_get).with(:@config_store).and_return(config_store)
      allow(config_store).to receive(:set_config)
      allow(Thread).to receive(:kill)
    end

    it "disables and stops conversation-summarizer" do
      mock_thread = instance_double(Thread, alive?: true)
      mock_worker = instance_double(
        Nu::Agent::Workers::ConversationSummarizer,
        start_worker: mock_thread
      )

      allow(Nu::Agent::Workers::ConversationSummarizer).to receive(:new).and_return(mock_worker)

      # Start first
      worker_manager.start_worker("conversation-summarizer")

      # Disable
      expect(config_store).to receive(:set_config).with("conversation_summarizer_enabled", "false")
      expect(Thread).to receive(:kill).with(mock_thread)
      result = worker_manager.disable_worker("conversation-summarizer")

      expect(result).to be true
    end

    it "returns false for invalid worker name" do
      result = worker_manager.disable_worker("invalid-worker")
      expect(result).to be false
    end

    it "only sets config if worker not running" do
      expect(config_store).to receive(:set_config).with("conversation_summarizer_enabled", "false")
      result = worker_manager.disable_worker("conversation-summarizer")

      expect(result).to be true
    end
  end
end
