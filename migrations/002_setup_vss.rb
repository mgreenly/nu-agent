# frozen_string_literal: true

# Migration: Setup VSS extension and create HNSW index for vector search
{
  version: 2,
  name: "setup_vss",
  up: lambda do |conn|
    # Try to load VSS extension and create HNSW index
    vss_available = false
    begin
      conn.query("LOAD vss")

      # Enable experimental persistence for HNSW indexes
      conn.query("SET hnsw_enable_experimental_persistence=true")

      # Create HNSW index for vector similarity search
      conn.query(<<~SQL)
        CREATE INDEX IF NOT EXISTS embedding_vss_idx
        ON text_embedding_3_small
        USING HNSW(embedding)
        WITH (metric = 'cosine')
      SQL

      vss_available = true
    rescue StandardError => e
      # VSS extension or HNSW index not available - will fall back to linear scan
      vss_available = false
      warn "⚠️  VSS extension not available: #{e.message}"
      warn "   Falling back to linear scan for similarity search"
    end

    # Store VSS availability in config for runtime checks
    conn.query("DELETE FROM appconfig WHERE key = 'vss_available'")
    conn.query(<<~SQL)
      INSERT INTO appconfig (key, value, updated_at)
      VALUES ('vss_available', '#{vss_available}', CURRENT_TIMESTAMP)
    SQL
  end
}
