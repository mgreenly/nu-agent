# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Workers::EmbeddingGenerator do
  subject(:pipeline) do
    described_class.new(
      history: history,
      embedding_client: embedding_client,
      application: application,
      status_info: status_info,
      current_conversation_id: 1,
      config_store: config_store
    )
  end

  let(:history) { double("history") }
  let(:embedding_client) { double("embedding_client") }
  let(:application) { double("application", instance_variable_get: false, embedding_enabled: true, debug: false) }
  let(:status) do
    { "running" => false, "total" => 0, "completed" => 0, "failed" => 0, "current_item" => nil, "spend" => 0.0 }
  end
  let(:status_mutex) { Mutex.new }
  let(:config_store) { double("config_store") }
  let(:status_info) { { status: status, mutex: status_mutex } }

  before do
    # Mock verbosity loading (default verbosity = 0)
    allow(config_store).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(0)
  end

  describe "#start_worker" do
    it "starts a background thread" do
      allow(history).to receive_messages(get_conversations_needing_embeddings: [], get_exchanges_needing_embeddings: [])

      thread = pipeline.start_worker
      expect(thread).to be_a(Thread)

      thread.join(1) # Wait up to 1 second for thread to complete
    end
  end

  describe "#process_embeddings" do
    context "when there are no items needing embeddings" do
      it "does not process anything" do
        allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return([])
        allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])

        pipeline.send(:process_embeddings)

        expect(status["total"]).to eq(0)
        expect(status["running"]).to be(false)
      end
    end

    context "when there are conversations needing embeddings" do
      let(:conversations) { [{ "id" => 2, "summary" => "Test conversation" }] }
      let(:embedding_response) do
        {
          "embeddings" => [Array.new(1536, 0.1)],
          "model" => "text-embedding-3-small",
          "tokens" => 10,
          "spend" => 0.0002
        }
      end

      before do
        allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return(conversations)
        allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
        allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
        allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
        allow(embedding_client).to receive(:generate_embedding).and_return(embedding_response)
        allow(history).to receive(:upsert_conversation_embedding)
        allow(application).to receive(:send).with(:enter_critical_section)
        allow(application).to receive(:send).with(:exit_critical_section)
      end

      it "processes conversations and generates embeddings" do
        pipeline.send(:process_embeddings)

        expect(history).to have_received(:upsert_conversation_embedding).with(
          conversation_id: 2,
          content: "Test conversation",
          embedding: embedding_response["embeddings"].first
        )
        expect(status["completed"]).to eq(1)
        expect(status["spend"]).to eq(0.0002)
      end
    end

    context "when there are exchanges needing embeddings" do
      let(:exchanges) { [{ "id" => 5, "summary" => "Test exchange" }] }
      let(:embedding_response) do
        {
          "embeddings" => [Array.new(1536, 0.2)],
          "model" => "text-embedding-3-small",
          "tokens" => 5,
          "spend" => 0.0001
        }
      end

      before do
        allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return([])
        allow(history).to receive(:get_exchanges_needing_embeddings)
          .with(exclude_conversation_id: 1).and_return(exchanges)
        allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
        allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
        allow(embedding_client).to receive(:generate_embedding).and_return(embedding_response)
        allow(history).to receive(:upsert_exchange_embedding)
        allow(application).to receive(:send).with(:enter_critical_section)
        allow(application).to receive(:send).with(:exit_critical_section)
      end

      it "processes exchanges and generates embeddings" do
        pipeline.send(:process_embeddings)

        expect(history).to have_received(:upsert_exchange_embedding).with(
          exchange_id: 5,
          content: "Test exchange",
          embedding: embedding_response["embeddings"].first
        )
        expect(status["completed"]).to eq(1)
      end
    end

    context "when shutdown is requested" do
      before do
        allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return([])
        allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
        allow(application).to receive(:instance_variable_get).with(:@shutdown).and_return(true)
      end

      it "stops processing early" do
        pipeline.send(:process_embeddings)

        expect(status["running"]).to be(false)
      end
    end
  end

  describe "batching behavior" do
    before do
      allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return(conversations)
      allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
      allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
      allow(embedding_client).to receive(:generate_embedding).and_return(embedding_response)
      allow(history).to receive(:upsert_conversation_embedding)
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
    end

    let(:conversations) do
      [
        { "id" => 2, "summary" => "Conv 1" },
        { "id" => 3, "summary" => "Conv 2" },
        { "id" => 4, "summary" => "Conv 3" }
      ]
    end
    let(:embedding_response) do
      {
        "embeddings" => [
          Array.new(1536, 0.1),
          Array.new(1536, 0.2),
          Array.new(1536, 0.3)
        ],
        "model" => "text-embedding-3-small",
        "tokens" => 30,
        "spend" => 0.0006
      }
    end

    it "batches multiple items together" do
      pipeline.send(:process_embeddings)

      expect(embedding_client).to have_received(:generate_embedding).once.with(["Conv 1", "Conv 2", "Conv 3"])
      expect(history).to have_received(:upsert_conversation_embedding).exactly(3).times
      expect(status["completed"]).to eq(3)
    end
  end

  describe "error handling" do
    before do
      allow(application).to receive(:debug).and_return(true)
      allow(application).to receive(:output_line)
      allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return(conversations)
      allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
      allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
      allow(embedding_client).to receive(:generate_embedding).and_return(error_response)
    end

    let(:conversations) { [{ "id" => 2, "summary" => "Test" }] }
    let(:error_response) { { "error" => { "status" => 500, "body" => "API Error" } } }

    it "handles API errors gracefully" do
      pipeline.send(:process_embeddings)

      expect(status["completed"]).to eq(0)
      expect(status["failed"]).to eq(1) # All items in failed batch are marked as failed
      expect(application).to have_received(:output_line).with(/\[EmbeddingGenerator\].*API error for batch of 1 items/,
                                                              type: :debug)
    end
  end

  describe "verbosity support" do
    let(:conversations) { [{ "id" => 2, "summary" => "Test conversation" }] }
    let(:embedding_response) do
      {
        "embeddings" => [Array.new(1536, 0.1)],
        "model" => "text-embedding-3-small",
        "tokens" => 10,
        "spend" => 0.0002
      }
    end

    before do
      allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return(conversations)
      allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
      allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
      allow(embedding_client).to receive(:generate_embedding).and_return(embedding_response)
      allow(history).to receive(:upsert_conversation_embedding)
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
      allow(application).to receive(:output_line)
    end

    describe "#load_verbosity" do
      it "loads verbosity from config store with default 0" do
        allow(config_store).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(2)
        expect(pipeline.send(:load_verbosity)).to eq(2)
      end

      it "defaults to 0 when not configured" do
        allow(config_store).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(0)
        expect(pipeline.send(:load_verbosity)).to eq(0)
      end
    end

    describe "#debug_output" do
      context "when debug is enabled" do
        before { allow(application).to receive(:debug).and_return(true) }

        it "outputs messages at or below verbosity level" do
          allow(config_store).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(2)
          pipeline = described_class.new(
            history: history,
            embedding_client: embedding_client,
            application: application,
            status_info: status_info,
            current_conversation_id: 1,
            config_store: config_store
          )

          pipeline.send(:debug_output, "Level 1 message", level: 1)
          expect(application).to have_received(:output_line).with("[EmbeddingGenerator] Level 1 message", type: :debug)
        end

        it "does not output messages above verbosity level" do
          allow(config_store).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(1)
          pipeline = described_class.new(
            history: history,
            embedding_client: embedding_client,
            application: application,
            status_info: status_info,
            current_conversation_id: 1,
            config_store: config_store
          )

          pipeline.send(:debug_output, "Level 3 message", level: 3)
          expect(application).not_to have_received(:output_line).with("[EmbeddingGenerator] Level 3 message",
                                                                      type: :debug)
        end
      end

      context "when debug is disabled" do
        before { allow(application).to receive(:debug).and_return(false) }

        it "does not output any messages" do
          allow(config_store).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(5)
          pipeline = described_class.new(
            history: history,
            embedding_client: embedding_client,
            application: application,
            status_info: status_info,
            current_conversation_id: 1,
            config_store: config_store
          )

          pipeline.send(:debug_output, "Test message", level: 0)
          expect(application).not_to have_received(:output_line).with("[EmbeddingGenerator] Test message", type: :debug)
        end
      end
    end

    describe "verbosity levels during processing" do
      before do
        allow(application).to receive(:debug).and_return(true)
      end

      it "outputs level 0 messages (worker lifecycle) when verbosity >= 0" do
        allow(config_store).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(0)
        pipeline = described_class.new(
          history: history,
          embedding_client: embedding_client,
          application: application,
          status_info: status_info,
          current_conversation_id: 1,
          config_store: config_store
        )

        pipeline.send(:process_embeddings)
        expect(application).to have_received(:output_line).with(/\[EmbeddingGenerator\].*Started/, type: :debug)
      end

      it "outputs level 1 messages (batch processing) when verbosity >= 1" do
        allow(config_store).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(1)
        pipeline = described_class.new(
          history: history,
          embedding_client: embedding_client,
          application: application,
          status_info: status_info,
          current_conversation_id: 1,
          config_store: config_store
        )

        pipeline.send(:process_embeddings)
        expect(application).to have_received(:output_line).with(/\[EmbeddingGenerator\].*batch/, type: :debug)
      end

      it "outputs level 2 messages (individual items) when verbosity >= 2" do
        allow(config_store).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(2)
        pipeline = described_class.new(
          history: history,
          embedding_client: embedding_client,
          application: application,
          status_info: status_info,
          current_conversation_id: 1,
          config_store: config_store
        )

        pipeline.send(:process_embeddings)
        expect(application).to have_received(:output_line).with(/\[EmbeddingGenerator\].*Processing conversation:2/,
                                                                type: :debug)
      end

      it "outputs level 3 messages (API responses) when verbosity >= 3" do
        allow(config_store).to receive(:get_int).with("embeddings_verbosity", default: 0).and_return(3)
        pipeline = described_class.new(
          history: history,
          embedding_client: embedding_client,
          application: application,
          status_info: status_info,
          current_conversation_id: 1,
          config_store: config_store
        )

        pipeline.send(:process_embeddings)
        expect(application).to have_received(:output_line).with(/\[EmbeddingGenerator\].*Stored embedding/,
                                                                type: :debug)
      end
    end
  end

  describe "item processing error handling" do
    let(:conversations) { [{ "id" => 2, "summary" => "Test conversation" }] }
    let(:embedding_response) do
      {
        "embeddings" => [Array.new(1536, 0.1)],
        "model" => "text-embedding-3-small",
        "tokens" => 10,
        "spend" => 0.0002
      }
    end

    before do
      allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return(conversations)
      allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
      allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
      allow(embedding_client).to receive(:generate_embedding).and_return(embedding_response)
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
      allow(application).to receive(:debug).and_return(true)
      allow(application).to receive(:output_line)
    end

    it "handles errors when storing embeddings and creates failed job record" do
      allow(history).to receive(:upsert_conversation_embedding).and_raise(StandardError.new("Database error"))
      allow(history).to receive(:create_failed_job)

      pipeline.send(:process_embeddings)

      expect(status["failed"]).to eq(1)
      expect(status["completed"]).to eq(0)
      expect(history).to have_received(:create_failed_job).with(
        job_type: "embedding_generation",
        ref_id: 2,
        payload: "{\"item_type\":\"conversation\",\"item_id\":2,\"worker\":\"embedding_generator\"}",
        error: "StandardError: Database error"
      )
      expect(application).to have_received(:output_line)
        .with(/\[EmbeddingGenerator\].*Failed to process conversation:2/, type: :debug)
    end

    it "handles errors when recording failed job" do
      allow(history).to receive(:upsert_conversation_embedding).and_raise(StandardError.new("Database error"))
      allow(history).to receive(:create_failed_job).and_raise(StandardError.new("Failed job recording error"))

      # Should not raise, just log the error
      expect { pipeline.send(:process_embeddings) }.not_to raise_error

      expect(status["failed"]).to eq(1)
      expect(application).to have_received(:output_line)
        .with(/\[EmbeddingGenerator\].*Failed to record failure/, type: :debug)
    end
  end

  describe "shutdown during API call" do
    let(:conversations) { [{ "id" => 2, "summary" => "Test conversation" }] }

    before do
      allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return(conversations)
      allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
      allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
    end

    it "stops waiting for API response when shutdown is requested" do
      # Simulate a slow API call
      api_thread = Thread.new do
        sleep(5)
        { "embeddings" => [Array.new(1536, 0.1)], "model" => "test", "tokens" => 10, "spend" => 0.0 }
      end

      # Simulate shutdown after a short delay
      allow(application).to receive(:instance_variable_get).with(:@shutdown).and_return(false, false, true)
      allow(api_thread).to receive(:join).and_call_original

      result = pipeline.send(:wait_for_api_response, api_thread)

      # Should return nil because shutdown was requested
      expect(result).to be_nil
      api_thread.kill # Clean up the thread
    end
  end

  describe "embedding_enabled flag" do
    context "when embeddings are disabled" do
      it "does not process embeddings" do
        allow(application).to receive(:embedding_enabled).and_return(false)
        allow(history).to receive(:get_conversations_needing_embeddings)
        allow(history).to receive(:get_exchanges_needing_embeddings)

        pipeline.send(:process_embeddings)

        expect(history).not_to have_received(:get_conversations_needing_embeddings)
        expect(status["running"]).to be(false)
      end
    end
  end

  describe "rate limiting" do
    let(:conversations) { [{ "id" => 2, "summary" => "Test conversation" }] }
    let(:embedding_response) do
      {
        "embeddings" => [Array.new(1536, 0.1)],
        "model" => "text-embedding-3-small",
        "tokens" => 10,
        "spend" => 0.0002
      }
    end

    before do
      allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return(conversations)
      allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
      allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
      allow(embedding_client).to receive(:generate_embedding).and_return(embedding_response)
      allow(history).to receive(:upsert_conversation_embedding)
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
    end

    it "applies rate limiting when configured" do
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(100)

      start_time = Time.now
      pipeline.send(:process_embeddings)
      elapsed = Time.now - start_time

      # Should have slept for ~100ms (0.1 seconds)
      expect(elapsed).to be >= 0.1
    end

    it "skips rate limiting when set to 0" do
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)

      start_time = Time.now
      pipeline.send(:process_embeddings)
      elapsed = Time.now - start_time

      # Should not have added significant delay
      expect(elapsed).to be < 0.05
    end

    it "skips rate limiting sleep when shutdown is requested" do
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(1000)
      allow(application).to receive(:instance_variable_get).with(:@shutdown).and_return(false, false, false, true)

      start_time = Time.now
      pipeline.send(:process_embeddings)
      elapsed = Time.now - start_time

      # Should not wait the full 1000ms because shutdown was requested
      expect(elapsed).to be < 0.5
    end
  end

  describe "shutdown during batch processing" do
    let(:conversations) do
      [
        { "id" => 2, "summary" => "Conv 1" },
        { "id" => 3, "summary" => "Conv 2" },
        { "id" => 4, "summary" => "Conv 3" }
      ]
    end

    before do
      allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return(conversations)
      allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
      allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(1)
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
      allow(embedding_client).to receive(:generate_embedding)
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
    end

    it "stops processing batches when shutdown is requested" do
      # Shutdown after first batch
      allow(application).to receive(:instance_variable_get).with(:@shutdown).and_return(false, false, true)

      pipeline.send(:process_embeddings)

      # Should not process all 3 batches
      expect(embedding_client).to have_received(:generate_embedding).at_most(2).times
    end
  end

  describe "missing embedding in response" do
    let(:conversations) { [{ "id" => 2, "summary" => "Test" }] }
    let(:embedding_response) do
      {
        "embeddings" => [nil],
        "model" => "text-embedding-3-small",
        "tokens" => 10,
        "spend" => 0.0002
      }
    end

    before do
      allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return(conversations)
      allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
      allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
      allow(embedding_client).to receive(:generate_embedding).and_return(embedding_response)
      allow(history).to receive(:upsert_conversation_embedding)
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
    end

    it "skips items with nil embeddings" do
      pipeline.send(:process_embeddings)

      expect(history).not_to have_received(:upsert_conversation_embedding)
      expect(status["completed"]).to eq(0)
    end
  end

  describe "shutdown during item processing" do
    let(:conversations) do
      [
        { "id" => 2, "summary" => "Conv 1" },
        { "id" => 3, "summary" => "Conv 2" }
      ]
    end
    let(:embedding_response) do
      {
        "embeddings" => [Array.new(1536, 0.1), Array.new(1536, 0.2)],
        "model" => "text-embedding-3-small",
        "tokens" => 20,
        "spend" => 0.0004
      }
    end

    before do
      allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return(conversations)
      allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
      allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
      allow(embedding_client).to receive(:generate_embedding).and_return(embedding_response)
      allow(history).to receive(:upsert_conversation_embedding)
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
    end

    it "stops processing items when shutdown is requested" do
      # Shutdown after processing first item
      call_count = 0
      allow(application).to receive(:instance_variable_get).with(:@shutdown) do
        call_count += 1
        call_count > 3
      end

      pipeline.send(:process_embeddings)

      # Should only process first item
      expect(history).to have_received(:upsert_conversation_embedding).at_most(1).times
    end
  end

  describe "retry logic" do
    let(:conversations) { [{ "id" => 2, "summary" => "Test" }] }
    let(:error_response) { { "error" => { "status" => 500, "body" => "Server error" } } }

    before do
      allow(history).to receive(:get_conversations_needing_embeddings).with(exclude_id: 1).and_return(conversations)
      allow(history).to receive(:get_exchanges_needing_embeddings).with(exclude_conversation_id: 1).and_return([])
      allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
      allow(application).to receive(:debug).and_return(true)
      allow(application).to receive(:output_line)
    end

    it "retries on error up to 3 times" do
      success_response = {
        "embeddings" => [Array.new(1536, 0.1)],
        "model" => "test",
        "tokens" => 10,
        "spend" => 0.0
      }

      allow(embedding_client).to receive(:generate_embedding)
        .and_return(error_response, error_response, success_response)
      allow(history).to receive(:upsert_conversation_embedding)

      pipeline.send(:process_embeddings)

      expect(embedding_client).to have_received(:generate_embedding).exactly(3).times
      expect(status["completed"]).to eq(1)
    end

    it "returns falsey from should_retry? when shutdown is requested" do
      # Test the should_retry? method directly
      allow(application).to receive(:instance_variable_get).with(:@shutdown).and_return(true)

      response = { "error" => { "status" => 500 } }
      result = pipeline.send(:should_retry?, response, 1, 3)

      expect(result).to be_falsey
    end

    it "returns falsey from should_retry? when at max attempts" do
      response = { "error" => { "status" => 500 } }
      result = pipeline.send(:should_retry?, response, 3, 3)

      expect(result).to be_falsey
    end

    it "returns falsey from should_retry? when response has no error" do
      response = { "embeddings" => [] }
      result = pipeline.send(:should_retry?, response, 1, 3)

      expect(result).to be_falsey
    end

    it "returns true from should_retry? when error and attempts remaining" do
      response = { "error" => { "status" => 500 } }
      result = pipeline.send(:should_retry?, response, 1, 3)

      expect(result).to be_truthy
    end

    it "stops retrying after max attempts" do
      allow(embedding_client).to receive(:generate_embedding).and_return(error_response)

      pipeline.send(:process_embeddings)

      expect(embedding_client).to have_received(:generate_embedding).exactly(3).times
      expect(status["failed"]).to eq(1)
    end

    it "does not retry when response is nil" do
      allow(embedding_client).to receive(:generate_embedding).and_return(nil)

      pipeline.send(:process_embeddings)

      expect(embedding_client).to have_received(:generate_embedding).once
    end
  end

  describe "empty batch handling" do
    before do
      allow(config_store).to receive(:get_int).with("embedding_batch_size", default: 10).and_return(10)
      allow(config_store).to receive(:get_int).with("embedding_rate_limit_ms", default: 100).and_return(0)
      allow(embedding_client).to receive(:generate_embedding)
    end

    it "skips processing when batch is empty" do
      # Create empty batch
      batch = []

      pipeline.send(:process_batch, batch)

      expect(embedding_client).not_to have_received(:generate_embedding)
    end
  end

  describe "api thread completion" do
    it "returns response when thread completes immediately" do
      response = { "embeddings" => [Array.new(1536, 0.1)], "model" => "test", "tokens" => 10, "spend" => 0.0 }
      api_thread = Thread.new { response }

      result = pipeline.send(:wait_for_api_response, api_thread)

      expect(result).to eq(response)
    end
  end

  describe "build_ids_display edge cases" do
    it "handles empty conversation and exchange IDs" do
      result = pipeline.send(:build_ids_display, "", "")

      expect(result).to eq([])
    end

    it "handles only conversation IDs" do
      result = pipeline.send(:build_ids_display, "1, 2", "")

      expect(result).to eq(["conversations: 1, 2"])
    end

    it "handles only exchange IDs" do
      result = pipeline.send(:build_ids_display, "", "3, 4")

      expect(result).to eq(["exchanges: 3, 4"])
    end
  end

  describe "store_embedding with unknown type" do
    it "does nothing when item type is neither conversation nor exchange" do
      item = { type: "unknown", id: 999, content: "Test" }
      embedding = Array.new(1536, 0.1)

      allow(history).to receive(:upsert_conversation_embedding)
      allow(history).to receive(:upsert_exchange_embedding)

      pipeline.send(:store_embedding, item, embedding)

      expect(history).not_to have_received(:upsert_conversation_embedding)
      expect(history).not_to have_received(:upsert_exchange_embedding)
    end
  end

  describe "sleep_with_backoff with shutdown" do
    it "does not sleep when shutdown is requested" do
      allow(application).to receive(:instance_variable_get).with(:@shutdown).and_return(true)

      start_time = Time.now
      pipeline.send(:sleep_with_backoff, 1)
      elapsed = Time.now - start_time

      # Should not sleep at all (elapsed should be negligible)
      expect(elapsed).to be < 0.1
    end
  end
end
