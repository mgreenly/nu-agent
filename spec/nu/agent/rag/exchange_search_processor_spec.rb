# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::RAG::ExchangeSearchProcessor do
  let(:embedding_store) { double("embedding_store") }
  let(:config_store) { double("config_store") }
  let(:processor) { described_class.new(embedding_store: embedding_store, config_store: config_store) }
  let(:context) { Nu::Agent::RAG::RAGContext.new(query: "test query") }
  let(:query_embedding) { Array.new(1536, 0.1) }

  before do
    # Mock config defaults
    allow(config_store).to receive(:get_int).with("rag_exchanges_per_conversation", default: 3).and_return(3)
    allow(config_store).to receive(:get_int).with("rag_exchange_global_cap", default: 10).and_return(10)
    allow(config_store).to receive(:get_float).with("rag_exchange_min_similarity", default: 0.6).and_return(0.6)
  end

  describe "#process" do
    context "when query_embedding is nil" do
      it "returns early without searching" do
        context.query_embedding = nil
        allow(embedding_store).to receive(:search_exchanges)

        processor.process(context)

        expect(embedding_store).not_to have_received(:search_exchanges)
        expect(context.exchanges).to be_empty
      end
    end

    context "when conversation_ids is empty" do
      before do
        context.query_embedding = query_embedding
        context.conversations = []
      end

      it "searches globally" do
        global_results = [
          { exchange_id: 1, content: "Global exchange 1", similarity: 0.8 },
          { exchange_id: 2, content: "Global exchange 2", similarity: 0.7 }
        ]

        allow(embedding_store).to receive(:search_exchanges).and_return(global_results)

        processor.process(context)

        expect(embedding_store).to have_received(:search_exchanges).with(
          query_embedding: query_embedding,
          limit: 10,
          min_similarity: 0.6,
          conversation_ids: nil,
          after_date: nil,
          before_date: nil,
          recency_weight: nil
        )
        expect(context.exchanges).to eq(global_results)
        expect(context.metadata[:exchange_count]).to eq(2)
      end
    end

    context "when conversation_ids has values" do
      before do
        context.query_embedding = query_embedding
        context.conversations = [
          { conversation_id: 1 },
          { conversation_id: 2 }
        ]
      end

      it "searches per conversation and sorts by similarity" do
        conv1_results = [
          { exchange_id: 1, content: "Conv 1 exchange 1", similarity: 0.9 },
          { exchange_id: 2, content: "Conv 1 exchange 2", similarity: 0.7 }
        ]
        conv2_results = [
          { exchange_id: 3, content: "Conv 2 exchange 1", similarity: 0.85 }
        ]

        allow(embedding_store).to receive(:search_exchanges)
          .with(hash_including(conversation_ids: [1]))
          .and_return(conv1_results)
        allow(embedding_store).to receive(:search_exchanges)
          .with(hash_including(conversation_ids: [2]))
          .and_return(conv2_results)

        processor.process(context)

        expect(context.exchanges.length).to eq(3)
        # Should be sorted by similarity descending
        expect(context.exchanges[0][:similarity]).to eq(0.9)
        expect(context.exchanges[1][:similarity]).to eq(0.85)
        expect(context.exchanges[2][:similarity]).to eq(0.7)
        expect(context.metadata[:exchange_count]).to eq(3)
      end

      it "sorts by blended_score when recency_weight is set" do
        context.recency_weight = 0.3

        conv1_results = [
          { exchange_id: 1, content: "Exchange 1", similarity: 0.8, blended_score: 0.85 }
        ]
        conv2_results = [
          { exchange_id: 2, content: "Exchange 2", similarity: 0.9, blended_score: 0.75 }
        ]

        allow(embedding_store).to receive(:search_exchanges)
          .with(hash_including(conversation_ids: [1]))
          .and_return(conv1_results)
        allow(embedding_store).to receive(:search_exchanges)
          .with(hash_including(conversation_ids: [2]))
          .and_return(conv2_results)

        processor.process(context)

        # Should be sorted by blended_score descending
        expect(context.exchanges[0][:blended_score]).to eq(0.85)
        expect(context.exchanges[1][:blended_score]).to eq(0.75)
      end

      it "applies global cap across all conversations" do
        # Set global cap to 2
        allow(config_store).to receive(:get_int).with("rag_exchange_global_cap", default: 10).and_return(2)

        conv1_results = [
          { exchange_id: 1, content: "Exchange 1", similarity: 0.9 },
          { exchange_id: 2, content: "Exchange 2", similarity: 0.8 }
        ]
        conv2_results = [
          { exchange_id: 3, content: "Exchange 3", similarity: 0.7 }
        ]

        allow(embedding_store).to receive(:search_exchanges)
          .with(hash_including(conversation_ids: [1]))
          .and_return(conv1_results)
        allow(embedding_store).to receive(:search_exchanges)
          .with(hash_including(conversation_ids: [2]))
          .and_return(conv2_results)

        processor.process(context)

        # Should only return top 2 by similarity
        expect(context.exchanges.length).to eq(2)
        expect(context.exchanges[0][:similarity]).to eq(0.9)
        expect(context.exchanges[1][:similarity]).to eq(0.8)
      end

      it "stops searching when global cap is reached during iteration" do
        # Set global cap to 2
        allow(config_store).to receive(:get_int).with("rag_exchange_global_cap", default: 10).and_return(2)

        # Add a third conversation to ensure break is tested
        context.conversations << { conversation_id: 3 }

        conv1_results = [
          { exchange_id: 1, content: "Exchange 1", similarity: 0.9 }
        ]
        conv2_results = [
          { exchange_id: 2, content: "Exchange 2", similarity: 0.8 }
        ]

        allow(embedding_store).to receive(:search_exchanges)
          .with(hash_including(conversation_ids: [1]))
          .and_return(conv1_results)
        allow(embedding_store).to receive(:search_exchanges)
          .with(hash_including(conversation_ids: [2]))
          .and_return(conv2_results)

        processor.process(context)

        # Should stop after second conversation and not search third
        expect(embedding_store).to have_received(:search_exchanges).twice
        expect(context.exchanges.length).to eq(2)
      end
    end
  end
end
