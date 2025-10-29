# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::EmbeddingStore do
  let(:test_db_path) { "db/test_embedding_store.db" }
  let(:db) { DuckDB::Database.open(test_db_path) }
  let(:connection) { db.connect }
  let(:embedding_store) { described_class.new(connection) }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }

  before do
    FileUtils.rm_rf(test_db_path)
    FileUtils.mkdir_p("db")
    # Setup schema so tables exist
    schema_manager.setup_schema
  end

  after do
    connection.close
    db.close
    FileUtils.rm_rf(test_db_path)
  end

  describe "#store_embeddings" do
    it "stores embedding records in the database" do
      records = [
        {
          source: "man:ls",
          content: "list directory contents",
          embedding: Array.new(1536, 0.1)
        },
        {
          source: "man:cd",
          content: "change directory",
          embedding: Array.new(1536, 0.2)
        }
      ]

      embedding_store.store_embeddings(kind: "man_pages", records: records)

      # Verify records were stored
      result = connection.query(<<~SQL)
        SELECT kind, source, content FROM text_embedding_3_small
        ORDER BY source
      SQL
      rows = result.to_a
      expect(rows.length).to eq(2)
      expect(rows[0][1]).to eq("man:cd")
      expect(rows[1][1]).to eq("man:ls")
    end

    it "does not duplicate records with same kind and source" do
      records = [
        {
          source: "man:ls",
          content: "list directory contents",
          embedding: Array.new(1536, 0.1)
        }
      ]

      embedding_store.store_embeddings(kind: "man_pages", records: records)
      embedding_store.store_embeddings(kind: "man_pages", records: records)

      # Should still only have one record
      result = connection.query("SELECT COUNT(*) FROM text_embedding_3_small")
      expect(result.to_a.first.first).to eq(1)
    end
  end

  describe "#get_indexed_sources" do
    before do
      records = [
        { source: "man:ls", content: "list", embedding: Array.new(1536, 0.1) },
        { source: "man:cd", content: "change", embedding: Array.new(1536, 0.2) }
      ]
      embedding_store.store_embeddings(kind: "man_pages", records: records)
    end

    it "returns all sources for a given kind" do
      sources = embedding_store.get_indexed_sources(kind: "man_pages")
      expect(sources).to contain_exactly("man:ls", "man:cd")
    end

    it "returns empty array when kind has no sources" do
      sources = embedding_store.get_indexed_sources(kind: "nonexistent")
      expect(sources).to eq([])
    end
  end

  describe "#embedding_stats" do
    before do
      man_records = [
        { source: "man:ls", content: "list", embedding: Array.new(1536, 0.1) },
        { source: "man:cd", content: "change", embedding: Array.new(1536, 0.2) }
      ]
      doc_records = [
        { source: "doc:readme", content: "readme", embedding: Array.new(1536, 0.3) }
      ]
      embedding_store.store_embeddings(kind: "man_pages", records: man_records)
      embedding_store.store_embeddings(kind: "docs", records: doc_records)
    end

    it "returns stats for all kinds when no kind specified" do
      stats = embedding_store.embedding_stats
      expect(stats.length).to eq(2)

      man_stat = stats.find { |s| s["kind"] == "man_pages" }
      doc_stat = stats.find { |s| s["kind"] == "docs" }

      expect(man_stat["count"]).to eq(2)
      expect(doc_stat["count"]).to eq(1)
    end

    it "returns stats for specific kind when specified" do
      stats = embedding_store.embedding_stats(kind: "man_pages")
      expect(stats.length).to eq(1)
      expect(stats.first["kind"]).to eq("man_pages")
      expect(stats.first["count"]).to eq(2)
    end
  end

  describe "#clear_embeddings" do
    before do
      man_records = [
        { source: "man:ls", content: "list", embedding: Array.new(1536, 0.1) }
      ]
      doc_records = [
        { source: "doc:readme", content: "readme", embedding: Array.new(1536, 0.3) }
      ]
      embedding_store.store_embeddings(kind: "man_pages", records: man_records)
      embedding_store.store_embeddings(kind: "docs", records: doc_records)
    end

    it "clears all embeddings for a specific kind" do
      embedding_store.clear_embeddings(kind: "man_pages")

      stats = embedding_store.embedding_stats
      expect(stats.length).to eq(1)
      expect(stats.first["kind"]).to eq("docs")
    end

    it "does not affect other kinds" do
      embedding_store.clear_embeddings(kind: "man_pages")

      doc_sources = embedding_store.get_indexed_sources(kind: "docs")
      expect(doc_sources).to eq(["doc:readme"])
    end
  end

  describe "#search_similar" do
    let(:query_embedding) { Array.new(1536) { |i| i < 100 ? 0.5 : 0.0 } }

    before do
      # Store some test embeddings with different similarity to query
      embedding_store.store_embeddings(
        kind: "test",
        records: [
          { source: "doc1", content: "very similar", embedding: Array.new(1536) { |i| i < 100 ? 0.51 : 0.0 } },
          { source: "doc2", content: "somewhat similar", embedding: Array.new(1536) { |i| i < 50 ? 0.5 : 0.0 } },
          { source: "doc3", content: "not similar", embedding: Array.new(1536) { |i| i > 1000 ? 0.5 : 0.0 } }
        ]
      )
    end

    it "returns results sorted by similarity (most similar first)" do
      results = embedding_store.search_similar(
        kind: "test",
        query_embedding: query_embedding,
        limit: 3
      )

      expect(results.length).to eq(3)
      expect(results[0][:source]).to eq("doc1") # Most similar
      expect(results[1][:source]).to eq("doc2") # Somewhat similar
      expect(results[2][:source]).to eq("doc3") # Least similar
    end

    it "respects the limit parameter" do
      results = embedding_store.search_similar(
        kind: "test",
        query_embedding: query_embedding,
        limit: 2
      )

      expect(results.length).to eq(2)
      expect(results[0][:source]).to eq("doc1")
      expect(results[1][:source]).to eq("doc2")
    end

    it "filters by kind" do
      embedding_store.store_embeddings(
        kind: "other",
        records: [
          { source: "other_doc", content: "other content", embedding: query_embedding }
        ]
      )

      results = embedding_store.search_similar(
        kind: "test",
        query_embedding: query_embedding,
        limit: 10
      )

      expect(results.length).to eq(3)
      expect(results.map { |r| r[:source] }).not_to include("other_doc")
    end

    it "returns content and similarity score" do
      results = embedding_store.search_similar(
        kind: "test",
        query_embedding: query_embedding,
        limit: 1
      )

      expect(results[0]).to have_key(:source)
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
        kind: "test",
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

  describe "#vss_available?" do
    it "returns boolean based on config" do
      # Default should be false or true depending on system
      result = embedding_store.vss_available?
      expect(result).to be(true).or be(false)
    end
  end
end
