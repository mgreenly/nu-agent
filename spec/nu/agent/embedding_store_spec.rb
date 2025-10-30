# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::EmbeddingStore do
  let(:test_db_path) { "db/test_embedding_store.db" }
  let(:db) { DuckDB::Database.open(test_db_path) }
  let(:connection) { db.connect }
  let(:embedding_store) { described_class.new(connection) }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }
  let(:migration_manager) { Nu::Agent::MigrationManager.new(connection) }

  before do
    FileUtils.rm_rf(test_db_path)
    FileUtils.mkdir_p("db")
    # Setup schema so tables exist
    schema_manager.setup_schema
    # Run migrations to apply schema changes (including conversation_id/exchange_id columns)
    migration_manager.run_pending_migrations
  end

  after do
    connection.close
    db.close
    FileUtils.rm_rf(test_db_path)
  end

  describe "#upsert_conversation_embedding" do
    it "stores conversation embedding in the database" do
      embedding_store.upsert_conversation_embedding(
        conversation_id: 1,
        content: "conversation summary",
        embedding: Array.new(1536, 0.1)
      )

      # Verify record was stored
      result = connection.query(<<~SQL)
        SELECT kind, conversation_id, content FROM text_embedding_3_small
      SQL
      rows = result.to_a
      expect(rows.length).to eq(1)
      expect(rows[0][0]).to eq("conversation_summary")
      expect(rows[0][1]).to eq(1)
      expect(rows[0][2]).to eq("conversation summary")
    end

    it "updates existing record for same conversation_id" do
      embedding_store.upsert_conversation_embedding(
        conversation_id: 1,
        content: "original content",
        embedding: Array.new(1536, 0.1)
      )

      embedding_store.upsert_conversation_embedding(
        conversation_id: 1,
        content: "updated content",
        embedding: Array.new(1536, 0.2)
      )

      # Should still only have one record with updated content
      result = connection.query("SELECT COUNT(*), content FROM text_embedding_3_small GROUP BY content")
      rows = result.to_a
      expect(rows.length).to eq(1)
      expect(rows[0][0]).to eq(1)
      expect(rows[0][1]).to eq("updated content")
    end
  end

  describe "#upsert_exchange_embedding" do
    it "stores exchange embedding in the database" do
      embedding_store.upsert_exchange_embedding(
        exchange_id: 5,
        content: "exchange summary",
        embedding: Array.new(1536, 0.3)
      )

      # Verify record was stored
      result = connection.query(<<~SQL)
        SELECT kind, exchange_id, content FROM text_embedding_3_small
      SQL
      rows = result.to_a
      expect(rows.length).to eq(1)
      expect(rows[0][0]).to eq("exchange_summary")
      expect(rows[0][1]).to eq(5)
      expect(rows[0][2]).to eq("exchange summary")
    end
  end

  describe "#get_indexed_sources" do
    before do
      embedding_store.upsert_conversation_embedding(
        conversation_id: 1,
        content: "first conversation",
        embedding: Array.new(1536, 0.1)
      )
      embedding_store.upsert_conversation_embedding(
        conversation_id: 2,
        content: "second conversation",
        embedding: Array.new(1536, 0.2)
      )
    end

    it "returns all source IDs for a given kind" do
      sources = embedding_store.get_indexed_sources(kind: "conversation_summary")
      expect(sources).to contain_exactly(1, 2)
    end

    it "returns empty array when kind has no sources" do
      sources = embedding_store.get_indexed_sources(kind: "nonexistent")
      expect(sources).to eq([])
    end
  end

  describe "#embedding_stats" do
    before do
      embedding_store.upsert_conversation_embedding(conversation_id: 1, content: "conv 1",
                                                    embedding: Array.new(1536, 0.1))
      embedding_store.upsert_conversation_embedding(conversation_id: 2, content: "conv 2",
                                                    embedding: Array.new(1536, 0.2))
      embedding_store.upsert_exchange_embedding(exchange_id: 10, content: "exch 10", embedding: Array.new(1536, 0.3))
    end

    it "returns stats for all kinds when no kind specified" do
      stats = embedding_store.embedding_stats
      expect(stats.length).to eq(2)

      conv_stat = stats.find { |s| s["kind"] == "conversation_summary" }
      exch_stat = stats.find { |s| s["kind"] == "exchange_summary" }

      expect(conv_stat["count"]).to eq(2)
      expect(exch_stat["count"]).to eq(1)
    end

    it "returns stats for specific kind when specified" do
      stats = embedding_store.embedding_stats(kind: "conversation_summary")
      expect(stats.length).to eq(1)
      expect(stats.first["kind"]).to eq("conversation_summary")
      expect(stats.first["count"]).to eq(2)
    end
  end

  describe "#clear_embeddings" do
    before do
      embedding_store.upsert_conversation_embedding(conversation_id: 1, content: "conv 1",
                                                    embedding: Array.new(1536, 0.1))
      embedding_store.upsert_exchange_embedding(exchange_id: 10, content: "exch 10", embedding: Array.new(1536, 0.3))
    end

    it "clears all embeddings for a specific kind" do
      embedding_store.clear_embeddings(kind: "conversation_summary")

      stats = embedding_store.embedding_stats
      expect(stats.length).to eq(1)
      expect(stats.first["kind"]).to eq("exchange_summary")
    end

    it "does not affect other kinds" do
      embedding_store.clear_embeddings(kind: "conversation_summary")

      exchange_sources = embedding_store.get_indexed_sources(kind: "exchange_summary")
      expect(exchange_sources).to eq([10])
    end
  end

  describe "#search_similar" do
    let(:query_embedding) { Array.new(1536) { |i| i < 100 ? 0.5 : 0.0 } }

    before do
      # Store some test embeddings with different similarity to query
      embedding_store.upsert_conversation_embedding(
        conversation_id: 1,
        content: "very similar",
        embedding: Array.new(1536) { |i| i < 100 ? 0.51 : 0.0 }
      )
      embedding_store.upsert_conversation_embedding(
        conversation_id: 2,
        content: "somewhat similar",
        embedding: Array.new(1536) { |i| i < 50 ? 0.5 : 0.0 }
      )
      embedding_store.upsert_conversation_embedding(
        conversation_id: 3,
        content: "not similar",
        embedding: Array.new(1536) { |i| i > 1000 ? 0.5 : 0.0 }
      )
    end

    it "returns results sorted by similarity (most similar first)" do
      results = embedding_store.search_similar(
        kind: "conversation_summary",
        query_embedding: query_embedding,
        limit: 3
      )

      expect(results.length).to eq(3)
      expect(results[0][:source_id]).to eq(1) # Most similar
      expect(results[1][:source_id]).to eq(2) # Somewhat similar
      expect(results[2][:source_id]).to eq(3) # Least similar
    end

    it "respects the limit parameter" do
      results = embedding_store.search_similar(
        kind: "conversation_summary",
        query_embedding: query_embedding,
        limit: 2
      )

      expect(results.length).to eq(2)
      expect(results[0][:source_id]).to eq(1)
      expect(results[1][:source_id]).to eq(2)
    end

    it "filters by kind" do
      embedding_store.upsert_exchange_embedding(
        exchange_id: 99,
        content: "other content",
        embedding: query_embedding
      )

      results = embedding_store.search_similar(
        kind: "conversation_summary",
        query_embedding: query_embedding,
        limit: 10
      )

      expect(results.length).to eq(3)
      expect(results.map { |r| r[:source_id] }).not_to include(99)
    end

    it "returns content and similarity score" do
      results = embedding_store.search_similar(
        kind: "conversation_summary",
        query_embedding: query_embedding,
        limit: 1
      )

      expect(results[0]).to have_key(:source_id)
      expect(results[0]).to have_key(:content)
      expect(results[0]).to have_key(:similarity)
      expect(results[0][:similarity]).to be_a(Float)
      expect(results[0][:similarity]).to be_between(0.0, 1.0)
    end

    it "handles empty result set" do
      results = embedding_store.search_similar(
        kind: "nonexistent",
        query_embedding: query_embedding,
        limit: 10
      )

      expect(results).to eq([])
    end

    it "supports min_similarity threshold" do
      results = embedding_store.search_similar(
        kind: "conversation_summary",
        query_embedding: query_embedding,
        limit: 10,
        min_similarity: 0.8
      )

      # Only very similar documents should be returned
      expect(results.length).to be <= 2
      results.each do |result|
        expect(result[:similarity]).to be >= 0.8
      end
    end
  end

  describe "#search_conversations" do
    let(:query_embedding) { Array.new(1536, 0.1) }

    before do
      # Create test conversations
      connection.query(<<~SQL)
        INSERT INTO conversations (id, created_at, title, status)
        VALUES (1, '2024-01-01 10:00:00', 'First', 'active'),
               (2, '2024-01-02 10:00:00', 'Second', 'active'),
               (3, '2024-01-03 10:00:00', 'Third', 'active')
      SQL

      # Store conversation embeddings
      embedding_store.upsert_conversation_embedding(
        conversation_id: 1,
        content: "conversation one",
        embedding: Array.new(1536, 0.1)
      )
      embedding_store.upsert_conversation_embedding(
        conversation_id: 2,
        content: "conversation two",
        embedding: Array.new(1536, 0.2)
      )
      embedding_store.upsert_conversation_embedding(
        conversation_id: 3,
        content: "conversation three",
        embedding: Array.new(1536, 0.3)
      )
    end

    it "searches for similar conversations" do
      results = embedding_store.search_conversations(
        query_embedding: query_embedding,
        limit: 5,
        min_similarity: 0.5
      )

      expect(results).to be_an(Array)
      expect(results.length).to be > 0
      expect(results.first).to have_key(:conversation_id)
      expect(results.first).to have_key(:content)
      expect(results.first).to have_key(:similarity)
      expect(results.first).to have_key(:created_at)
    end

    it "excludes specified conversation" do
      results = embedding_store.search_conversations(
        query_embedding: query_embedding,
        limit: 5,
        min_similarity: 0.5,
        exclude_conversation_id: 1
      )

      conversation_ids = results.map { |r| r[:conversation_id] }
      expect(conversation_ids).not_to include(1)
    end

    it "respects the limit parameter" do
      results = embedding_store.search_conversations(
        query_embedding: query_embedding,
        limit: 2,
        min_similarity: 0.0
      )

      expect(results.length).to be <= 2
    end

    it "applies min_similarity threshold" do
      results = embedding_store.search_conversations(
        query_embedding: query_embedding,
        limit: 10,
        min_similarity: 0.9
      )

      results.each do |result|
        expect(result[:similarity]).to be >= 0.9
      end
    end

    it "orders results by similarity descending" do
      results = embedding_store.search_conversations(
        query_embedding: query_embedding,
        limit: 5,
        min_similarity: 0.0
      )

      # Check that results are sorted by similarity (highest first)
      similarities = results.map { |r| r[:similarity] }
      expect(similarities).to eq(similarities.sort.reverse)
    end
  end

  describe "#search_exchanges" do
    let(:query_embedding) { Array.new(1536, 0.1) }

    before do
      # Create test conversations
      connection.query(<<~SQL)
        INSERT INTO conversations (id, created_at, title, status)
        VALUES (1, '2024-01-01 10:00:00', 'First', 'active'),
               (2, '2024-01-02 10:00:00', 'Second', 'active')
      SQL

      # Create test exchanges
      connection.query(<<~SQL)
        INSERT INTO exchanges (id, conversation_id, exchange_number, started_at, completed_at, status)
        VALUES (10, 1, 1, '2024-01-01 10:00:00', '2024-01-01 10:01:00', 'completed'),
               (11, 1, 2, '2024-01-01 10:05:00', '2024-01-01 10:06:00', 'completed'),
               (20, 2, 1, '2024-01-02 10:00:00', '2024-01-02 10:01:00', 'completed'),
               (21, 2, 2, '2024-01-02 10:05:00', '2024-01-02 10:06:00', 'completed')
      SQL

      # Store exchange embeddings
      embedding_store.upsert_exchange_embedding(
        exchange_id: 10,
        content: "exchange ten",
        embedding: Array.new(1536, 0.1)
      )
      embedding_store.upsert_exchange_embedding(
        exchange_id: 11,
        content: "exchange eleven",
        embedding: Array.new(1536, 0.2)
      )
      embedding_store.upsert_exchange_embedding(
        exchange_id: 20,
        content: "exchange twenty",
        embedding: Array.new(1536, 0.3)
      )
      embedding_store.upsert_exchange_embedding(
        exchange_id: 21,
        content: "exchange twenty-one",
        embedding: Array.new(1536, 0.4)
      )
    end

    it "searches for similar exchanges globally when conversation_ids is nil" do
      results = embedding_store.search_exchanges(
        query_embedding: query_embedding,
        limit: 5,
        min_similarity: 0.5,
        conversation_ids: nil
      )

      expect(results).to be_an(Array)
      expect(results.length).to be > 0
      expect(results.first).to have_key(:exchange_id)
      expect(results.first).to have_key(:conversation_id)
      expect(results.first).to have_key(:content)
      expect(results.first).to have_key(:similarity)
      expect(results.first).to have_key(:started_at)
    end

    it "filters by conversation_ids when provided" do
      results = embedding_store.search_exchanges(
        query_embedding: query_embedding,
        limit: 10,
        min_similarity: 0.0,
        conversation_ids: [1]
      )

      conversation_ids = results.map { |r| r[:conversation_id] }
      expect(conversation_ids).to all(eq(1))
    end

    it "supports multiple conversation_ids" do
      results = embedding_store.search_exchanges(
        query_embedding: query_embedding,
        limit: 10,
        min_similarity: 0.0,
        conversation_ids: [1, 2]
      )

      conversation_ids = results.map { |r| r[:conversation_id] }.uniq
      expect(conversation_ids).to contain_exactly(1, 2)
    end

    it "respects the limit parameter" do
      results = embedding_store.search_exchanges(
        query_embedding: query_embedding,
        limit: 2,
        min_similarity: 0.0,
        conversation_ids: nil
      )

      expect(results.length).to be <= 2
    end

    it "applies min_similarity threshold" do
      results = embedding_store.search_exchanges(
        query_embedding: query_embedding,
        limit: 10,
        min_similarity: 0.9,
        conversation_ids: nil
      )

      results.each do |result|
        expect(result[:similarity]).to be >= 0.9
      end
    end

    it "orders results by similarity descending" do
      results = embedding_store.search_exchanges(
        query_embedding: query_embedding,
        limit: 5,
        min_similarity: 0.0,
        conversation_ids: nil
      )

      # Check that results are sorted by similarity (highest first)
      similarities = results.map { |r| r[:similarity] }
      expect(similarities).to eq(similarities.sort.reverse)
    end
  end

  describe "#vss_available?" do
    it "returns boolean based on config" do
      # Default should be false or true depending on system
      result = embedding_store.vss_available?
      expect(result).to be(true).or be(false)
    end
  end
end
