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
  let(:application) { double("application", instance_variable_get: false, embedding_enabled: true) }
  let(:status) do
    { "running" => false, "total" => 0, "completed" => 0, "failed" => 0, "current_item" => nil, "spend" => 0.0 }
  end
  let(:status_mutex) { Mutex.new }
  let(:config_store) { double("config_store") }
  let(:status_info) { { status: status, mutex: status_mutex } }

  describe "#start_worker" do
    it "starts a background thread" do
      allow(history).to receive_messages(get_conversations_needing_embeddings: [], get_exchanges_needing_embeddings: [])

      thread = pipeline.start_worker
      expect(thread).to be_a(Thread)

      thread.join(1) # Wait up to 1 second for thread to complete
    end
  end

  describe "#process_embeddings" do
    before do
      # Mock debug output
      allow(application).to receive(:output_line)
    end

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
      # Mock debug output
      allow(application).to receive(:output_line)
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
      # Mock debug output
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
      expect(application).to have_received(:output_line).with(/API error for batch of 1 items/, type: :debug)
    end
  end
end
