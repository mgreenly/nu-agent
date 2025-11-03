# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::RAG::RAGRetriever do
  subject(:retriever) do
    described_class.new(
      embedding_store: embedding_store,
      embedding_client: embedding_client,
      config_store: config_store,
      retrieval_logger: retrieval_logger
    )
  end

  let(:embedding_store) { double("embedding_store") }
  let(:embedding_client) { double("embedding_client") }
  let(:config_store) { double("config_store") }
  let(:retrieval_logger) { nil }

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
        exclude_conversation_id: 10,
        after_date: nil,
        before_date: nil,
        recency_weight: nil
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
          conversation_ids: nil,
          after_date: nil,
          before_date: nil,
          recency_weight: nil
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

    context "with retrieval logger" do
      let(:retrieval_logger) { instance_double(Nu::Agent::RAG::RAGRetrievalLogger) }

      before do
        allow(retrieval_logger).to receive(:generate_query_hash).and_return("abc123")
        allow(retrieval_logger).to receive(:log_retrieval)
      end

      it "logs retrieval metrics when logger is provided" do
        retriever.retrieve(query: query, current_conversation_id: 1)

        expect(retrieval_logger).to have_received(:generate_query_hash).with(query_embedding, precision: 3)
        expect(retrieval_logger).to have_received(:log_retrieval).with(
          hash_including(
            query_hash: "abc123",
            conversation_candidates: 1,
            exchange_candidates: 1,
            retrieval_duration_ms: be > 0,
            top_conversation_score: 0.85,
            top_exchange_score: 0.78,
            cache_hit: false
          )
        )
      end

      it "does not fail when logger is nil" do
        retriever_without_logger = described_class.new(
          embedding_store: embedding_store,
          embedding_client: embedding_client,
          config_store: config_store,
          retrieval_logger: nil
        )

        expect { retriever_without_logger.retrieve(query: query) }.not_to raise_error
      end
    end

    context "with cache enabled" do
      let(:cache) { Nu::Agent::RAG::RAGCache.new(max_size: 10, ttl_seconds: 300) }
      let(:retriever_with_cache) do
        described_class.new(
          embedding_store: embedding_store,
          embedding_client: embedding_client,
          config_store: config_store,
          retrieval_logger: retrieval_logger,
          cache: cache
        )
      end
      let(:retrieval_logger) { instance_double(Nu::Agent::RAG::RAGRetrievalLogger) }

      before do
        allow(retrieval_logger).to receive(:generate_query_hash).and_return("abc123")
        allow(retrieval_logger).to receive(:log_retrieval)
      end

      it "caches retrieval results on first call" do
        context = retriever_with_cache.retrieve(query: query, current_conversation_id: 1)

        expect(context.conversations).to eq(conversation_results)
        expect(context.exchanges).to eq(exchange_results)
        expect(embedding_client).to have_received(:generate_embedding).once
        expect(embedding_store).to have_received(:search_conversations).once
      end

      it "returns cached results on subsequent calls with same query and config" do
        # First call - populates cache
        retriever_with_cache.retrieve(query: query, current_conversation_id: 1)

        # Second call - should use cache
        context = retriever_with_cache.retrieve(query: query, current_conversation_id: 1)

        expect(context.conversations).to eq(conversation_results)
        expect(context.exchanges).to eq(exchange_results)
        # Should still call embedding client once more (to generate key), but not search
        expect(embedding_client).to have_received(:generate_embedding).twice
        expect(embedding_store).to have_received(:search_conversations).once # Still just once!
        expect(embedding_store).to have_received(:search_exchanges).once
      end

      it "logs cache_hit: true when cache is used" do
        # First call
        retriever_with_cache.retrieve(query: query, current_conversation_id: 1)

        # Second call should be a cache hit
        retriever_with_cache.retrieve(query: query, current_conversation_id: 1)

        expect(retrieval_logger).to have_received(:log_retrieval).with(
          hash_including(cache_hit: false)
        ).once

        expect(retrieval_logger).to have_received(:log_retrieval).with(
          hash_including(cache_hit: true)
        ).once
      end

      it "bypasses cache for different queries" do
        retriever_with_cache.retrieve(query: query, current_conversation_id: 1)

        different_query = "How do I set up authentication?"
        allow(embedding_client).to receive(:generate_embedding).with(different_query)
                                                               .and_return({ "embeddings" => Array.new(1536, 0.9) })

        retriever_with_cache.retrieve(query: different_query, current_conversation_id: 1)

        expect(embedding_store).to have_received(:search_conversations).twice
      end

      it "bypasses cache for different conversation IDs" do
        retriever_with_cache.retrieve(query: query, current_conversation_id: 1)
        retriever_with_cache.retrieve(query: query, current_conversation_id: 2)

        expect(embedding_store).to have_received(:search_conversations).twice
      end

      it "bypasses cache for different time filters" do
        retriever_with_cache.retrieve(query: query, current_conversation_id: 1, after_date: "2025-01-01")
        retriever_with_cache.retrieve(query: query, current_conversation_id: 1, after_date: "2025-01-15")

        expect(embedding_store).to have_received(:search_conversations).twice
      end

      it "works correctly when cache is not provided (nil)" do
        retriever_without_cache = described_class.new(
          embedding_store: embedding_store,
          embedding_client: embedding_client,
          config_store: config_store,
          cache: nil
        )

        context = retriever_without_cache.retrieve(query: query)
        expect(context.formatted_context).not_to be_nil
      end

      it "handles nil embedding_response when cache is enabled" do
        # Mock the second call for fallback pipeline
        call_count = 0
        allow(embedding_client).to receive(:generate_embedding) do
          call_count += 1
          call_count == 1 ? nil : embedding_response
        end

        context = retriever_with_cache.retrieve(query: query)

        # Should fall back to normal pipeline and succeed
        expect(context.query_embedding).to eq(query_embedding)
        expect(context.formatted_context).not_to be_nil
      end

      it "handles embedding_response with nil embeddings when cache is enabled" do
        # Mock the second call for fallback pipeline
        call_count = 0
        allow(embedding_client).to receive(:generate_embedding) do
          call_count += 1
          call_count == 1 ? { "model" => "test" } : embedding_response
        end

        context = retriever_with_cache.retrieve(query: query)

        # Should fall back to normal pipeline when embeddings key is missing
        expect(context.query_embedding).to eq(query_embedding)
        expect(context.formatted_context).not_to be_nil
      end
    end

    context "with retrieval logger and edge cases" do
      let(:retrieval_logger) { instance_double(Nu::Agent::RAG::RAGRetrievalLogger) }

      before do
        allow(retrieval_logger).to receive(:generate_query_hash).and_return("abc123")
        allow(retrieval_logger).to receive(:log_retrieval)
      end

      it "skips logging when query_embedding is nil" do
        retriever_with_logger = described_class.new(
          embedding_store: embedding_store,
          embedding_client: embedding_client,
          config_store: config_store,
          retrieval_logger: retrieval_logger
        )

        allow(embedding_client).to receive(:generate_embedding).and_return({ "error" => { "status" => 500 } })

        retriever_with_logger.retrieve(query: query)

        # Should not call generate_query_hash when query_embedding is nil
        expect(retrieval_logger).not_to have_received(:generate_query_hash)
        expect(retrieval_logger).not_to have_received(:log_retrieval)
      end

      it "handles nil scores when conversations and exchanges are empty" do
        retriever_with_logger = described_class.new(
          embedding_store: embedding_store,
          embedding_client: embedding_client,
          config_store: config_store,
          retrieval_logger: retrieval_logger
        )

        # Mock empty results
        allow(embedding_store).to receive_messages(search_conversations: [], search_exchanges: [])

        retriever_with_logger.retrieve(query: query)

        # Should log with nil scores when arrays are empty
        expect(retrieval_logger).to have_received(:log_retrieval).with(
          hash_including(
            top_conversation_score: nil,
            top_exchange_score: nil
          )
        )
      end
    end

    context "with cache enabled but no logger" do
      let(:cache) { Nu::Agent::RAG::RAGCache.new(max_size: 10, ttl_seconds: 300) }
      let(:retriever_with_cache_no_logger) do
        described_class.new(
          embedding_store: embedding_store,
          embedding_client: embedding_client,
          config_store: config_store,
          retrieval_logger: nil,
          cache: cache
        )
      end

      it "handles cache hit without logger" do
        # First call - populates cache
        retriever_with_cache_no_logger.retrieve(query: query, current_conversation_id: 1)

        # Second call - cache hit without logger
        context = retriever_with_cache_no_logger.retrieve(query: query, current_conversation_id: 1)

        expect(context.conversations).to eq(conversation_results)
        expect(context.exchanges).to eq(exchange_results)
        # Should use cache and not fail
        expect(embedding_store).to have_received(:search_conversations).once
      end

      it "handles cache miss without logger" do
        # Call with cache miss - should not fail without logger
        context = retriever_with_cache_no_logger.retrieve(query: query, current_conversation_id: 1)

        expect(context.conversations).to eq(conversation_results)
        expect(context.exchanges).to eq(exchange_results)
      end
    end
  end
end
