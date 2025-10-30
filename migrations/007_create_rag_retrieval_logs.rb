# frozen_string_literal: true

# Migration: Create rag_retrieval_logs table for RAG retrieval observability
{
  version: 7,
  name: "create_rag_retrieval_logs",
  up: lambda do |conn|
    # Create sequence for rag_retrieval_logs id
    conn.query("CREATE SEQUENCE IF NOT EXISTS rag_retrieval_logs_id_seq START 1")

    # Create rag_retrieval_logs table
    conn.query(<<~SQL)
      CREATE TABLE IF NOT EXISTS rag_retrieval_logs (
        id INTEGER PRIMARY KEY DEFAULT nextval('rag_retrieval_logs_id_seq'),
        query_hash VARCHAR NOT NULL,
        timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        conversation_candidates INTEGER DEFAULT 0,
        exchange_candidates INTEGER DEFAULT 0,
        retrieval_duration_ms INTEGER NOT NULL,
        top_conversation_score FLOAT,
        top_exchange_score FLOAT,
        filtered_by TEXT,
        cache_hit BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    SQL

    # Create indexes for common queries
    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_rag_logs_timestamp
      ON rag_retrieval_logs(timestamp DESC)
    SQL

    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_rag_logs_query_hash
      ON rag_retrieval_logs(query_hash)
    SQL

    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_rag_logs_cache_hit
      ON rag_retrieval_logs(cache_hit)
    SQL
  end
}
