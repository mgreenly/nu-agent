# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::RAG::RAGRetrievalLogger do
  let(:connection) { DuckDB::Database.open.connect }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }
  let(:migration_manager) { Nu::Agent::MigrationManager.new(connection) }
  let(:logger) { described_class.new(connection) }

  before do
    schema_manager.setup_schema
    migration_manager.run_pending_migrations
  end

  after do
    connection.close
  end

  describe "#log_retrieval" do
    let(:retrieval_data) do
      {
        query_hash: "abc123",
        conversation_candidates: 5,
        exchange_candidates: 10,
        retrieval_duration_ms: 150,
        top_conversation_score: 0.85,
        top_exchange_score: 0.72,
        filtered_by: "time_range:recent",
        cache_hit: false
      }
    end

    it "logs retrieval metrics to the database" do
      logger.log_retrieval(retrieval_data)

      result = connection.query("SELECT COUNT(*) FROM rag_retrieval_logs")
      expect(result.to_a.first[0]).to eq(1)
    end

    it "stores all provided fields correctly" do
      logger.log_retrieval(retrieval_data)

      result = connection.query(<<~SQL)
        SELECT query_hash, conversation_candidates, exchange_candidates,
               retrieval_duration_ms, top_conversation_score, top_exchange_score,
               filtered_by, cache_hit
        FROM rag_retrieval_logs
        WHERE query_hash = 'abc123'
      SQL

      row = result.to_a.first
      expect(row[0]).to eq("abc123")
      expect(row[1]).to eq(5)
      expect(row[2]).to eq(10)
      expect(row[3]).to eq(150)
      expect(row[4]).to be_within(0.01).of(0.85)
      expect(row[5]).to be_within(0.01).of(0.72)
      expect(row[6]).to eq("time_range:recent")
      expect(row[7]).to be false
    end

    it "handles nil optional fields gracefully" do
      minimal_data = {
        query_hash: "xyz789",
        conversation_candidates: 0,
        exchange_candidates: 0,
        retrieval_duration_ms: 50,
        cache_hit: false
      }

      expect { logger.log_retrieval(minimal_data) }.not_to raise_error

      result = connection.query("SELECT COUNT(*) FROM rag_retrieval_logs WHERE query_hash = 'xyz789'")
      expect(result.to_a.first[0]).to eq(1)
    end

    it "handles cache hits correctly" do
      cache_hit_data = retrieval_data.merge(cache_hit: true)
      logger.log_retrieval(cache_hit_data)

      result = connection.query("SELECT cache_hit FROM rag_retrieval_logs WHERE query_hash = 'abc123'")
      expect(result.to_a.first[0]).to be true
    end
  end

  describe "#generate_query_hash" do
    it "generates consistent hash for same query embedding" do
      embedding = Array.new(1536, 0.1)
      hash1 = logger.generate_query_hash(embedding)
      hash2 = logger.generate_query_hash(embedding)

      expect(hash1).to eq(hash2)
      expect(hash1).to be_a(String)
      expect(hash1.length).to be > 0
    end

    it "generates different hashes for different embeddings" do
      embedding1 = Array.new(1536, 0.1)
      embedding2 = Array.new(1536, 0.2)

      hash1 = logger.generate_query_hash(embedding1)
      hash2 = logger.generate_query_hash(embedding2)

      expect(hash1).not_to eq(hash2)
    end

    it "uses rounding precision to group similar embeddings" do
      # Embeddings that differ only in digits beyond the precision should hash the same
      embedding1 = Array.new(1536, 0.1234567)
      embedding2 = Array.new(1536, 0.1234589)

      hash1 = logger.generate_query_hash(embedding1, precision: 4)
      hash2 = logger.generate_query_hash(embedding2, precision: 4)

      # With precision of 4 decimal places, both round to 0.1235 and should hash the same
      expect(hash1).to eq(hash2)
    end
  end

  describe "#get_recent_logs" do
    before do
      3.times do |i|
        logger.log_retrieval(
          query_hash: "hash_#{i}",
          conversation_candidates: i,
          exchange_candidates: i * 2,
          retrieval_duration_ms: 100 + (i * 10),
          cache_hit: (i % 2).zero?
        )
      end
    end

    it "retrieves recent logs" do
      logs = logger.get_recent_logs(limit: 5)

      expect(logs.length).to eq(3)
      expect(logs).to all(be_a(Hash))
      expect(logs.first).to have_key(:query_hash)
      expect(logs.first).to have_key(:retrieval_duration_ms)
    end

    it "respects the limit parameter" do
      logs = logger.get_recent_logs(limit: 2)

      expect(logs.length).to eq(2)
    end

    it "orders by timestamp descending (most recent first)" do
      logs = logger.get_recent_logs(limit: 5)

      # Most recent should be hash_2 (last inserted)
      expect(logs.first[:query_hash]).to eq("hash_2")
    end
  end
end
