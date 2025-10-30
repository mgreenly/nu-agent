# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::RAG::RAGRetriever do
  subject(:retriever) do
    described_class.new(
      embedding_store: embedding_store,
      embedding_client: embedding_client,
      config_store: config_store
    )
  end

  let(:embedding_store) { double("embedding_store") }
  let(:embedding_client) { double("embedding_client") }
  let(:config_store) { double("config_store") }

  describe "#retrieve" do
    let(:query) { "How do I configure the database?" }
    let(:query_embedding) { Array.new(1536, 0.1) }
    let(:embedding_response) do
      {
        "embeddings" => query_embedding,
        "model" => "text-embedding-3-small",
        "tokens" => 10,
        "spend" => 0.0002
      }
    end

    let(:conversation_results) do
      [
        {
          conversation_id: 5,
          content: "Discussion about database configuration",
          created_at: Time.now - 3600,
          similarity: 0.85
        }
      ]
    end

    let(:exchange_results) do
      [
        {
          exchange_id: 12,
          conversation_id: 5,
          content: "User asked about connection pooling",
          started_at: Time.now - 1800,
          similarity: 0.78
        }
      ]
    end

    before do
      # Mock embedding client
      allow(embedding_client).to receive(:generate_embedding).with(query).and_return(embedding_response)

      # Mock config store
      allow(config_store).to receive(:get_int).with("rag_conversation_limit", default: 5).and_return(5)
      allow(config_store).to receive(:get_float).with("rag_conversation_min_similarity", default: 0.7).and_return(0.7)
      allow(config_store).to receive(:get_int).with("rag_exchanges_per_conversation", default: 3).and_return(3)
      allow(config_store).to receive(:get_int).with("rag_exchange_global_cap", default: 10).and_return(10)
      allow(config_store).to receive(:get_float).with("rag_exchange_min_similarity", default: 0.6).and_return(0.6)
      allow(config_store).to receive(:get_int).with("rag_token_budget", default: 2000).and_return(2000)
      allow(config_store).to receive(:get_float).with("rag_conversation_budget_pct", default: 0.4).and_return(0.4)

      # Mock embedding store searches
      allow(embedding_store).to receive_messages(search_conversations: conversation_results,
                                                 search_exchanges: exchange_results)
    end

    it "returns a RAGContext with formatted context" do
      context = retriever.retrieve(query: query, current_conversation_id: 1)

      expect(context).to be_a(Nu::Agent::RAG::RAGContext)
      expect(context.query).to eq(query)
      expect(context.query_embedding).to eq(query_embedding)
      expect(context.conversations).to eq(conversation_results)
      expect(context.exchanges).to eq(exchange_results)
      expect(context.formatted_context).not_to be_nil
      expect(context.formatted_context).to include("Related Conversations")
      expect(context.formatted_context).to include("Related Exchanges")
    end

    it "tracks metadata including timing" do
      context = retriever.retrieve(query: query)

      expect(context.metadata[:start_time]).not_to be_nil
      expect(context.metadata[:end_time]).not_to be_nil
      expect(context.metadata[:duration_ms]).to be > 0
      expect(context.metadata[:conversation_count]).to eq(1)
      expect(context.metadata[:exchange_count]).to eq(1)
    end

    it "excludes current conversation" do
      retriever.retrieve(query: query, current_conversation_id: 10)

      expect(embedding_store).to have_received(:search_conversations).with(
        query_embedding: query_embedding,
        limit: 5,
        min_similarity: 0.7,
        exclude_conversation_id: 10
      )
    end

    context "when no conversations are found" do
      before do
        allow(embedding_store).to receive(:search_conversations).and_return([])
      end

      it "searches globally for exchanges" do
        retriever.retrieve(query: query)

        expect(embedding_store).to have_received(:search_exchanges).with(
          query_embedding: query_embedding,
          limit: 10,
          min_similarity: 0.6,
          conversation_ids: nil
        )
      end
    end

    context "when embedding generation fails" do
      before do
        allow(embedding_client).to receive(:generate_embedding).and_return({ "error" => { "status" => 500 } })
      end

      it "returns context without embeddings or results" do
        context = retriever.retrieve(query: query)

        expect(context.query_embedding).to be_nil
        expect(context.conversations).to be_empty
        expect(context.exchanges).to be_empty
      end
    end
  end
end
