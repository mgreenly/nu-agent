# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Migration 007: Create rag_retrieval_logs" do
  let(:connection) { DuckDB::Database.open.connect }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }
  let(:migration) { eval(File.read("migrations/007_create_rag_retrieval_logs.rb")) } # rubocop:disable Security/Eval

  before do
    schema_manager.setup_schema
  end

  after do
    connection.close
  end

  describe "up migration" do
    it "creates rag_retrieval_logs table with correct schema" do
      silence_migration { migration[:up].call(connection) }

      tables = connection.query("SHOW TABLES").map { |row| row[0] }
      expect(tables).to include("rag_retrieval_logs")

      columns = connection.query("DESCRIBE rag_retrieval_logs").map { |row| row[0] }
      expect(columns).to include("id", "query_hash", "timestamp", "conversation_candidates",
                                 "exchange_candidates", "retrieval_duration_ms",
                                 "top_conversation_score", "top_exchange_score", "filtered_by",
                                 "cache_hit", "created_at")
    end

    it "creates required indexes" do
      silence_migration { migration[:up].call(connection) }

      # Check that indexes were created (DuckDB way)
      result = connection.query("SELECT index_name FROM duckdb_indexes() WHERE table_name = 'rag_retrieval_logs'")
      index_names = result.map { |row| row[0] }

      expect(index_names).to include("idx_rag_logs_timestamp")
      expect(index_names).to include("idx_rag_logs_query_hash")
      expect(index_names).to include("idx_rag_logs_cache_hit")
    end

    it "is idempotent (can run twice without error)" do
      silence_migration { migration[:up].call(connection) }
      expect { silence_migration { migration[:up].call(connection) } }.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/DescribeClass
