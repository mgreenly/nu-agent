# frozen_string_literal: true

# Migration: Add conversation_id and exchange_id foreign keys to embeddings table
{
  version: 1,
  name: "add_embedding_constraints",
  up: lambda do |conn|
    # Check if conversation_id column exists
    result = conn.query(<<~SQL)
      SELECT COUNT(*) FROM information_schema.columns
      WHERE table_name = 'text_embedding_3_small' AND column_name = 'conversation_id'
    SQL
    has_conversation_id = result.to_a.first[0].positive?

    # Add conversation_id column if it doesn't exist
    unless has_conversation_id
      conn.query(<<~SQL)
        ALTER TABLE text_embedding_3_small
        ADD COLUMN conversation_id INTEGER
      SQL
    end

    # Check if exchange_id column exists
    result = conn.query(<<~SQL)
      SELECT COUNT(*) FROM information_schema.columns
      WHERE table_name = 'text_embedding_3_small' AND column_name = 'exchange_id'
    SQL
    has_exchange_id = result.to_a.first[0].positive?

    # Add exchange_id column if it doesn't exist
    unless has_exchange_id
      conn.query(<<~SQL)
        ALTER TABLE text_embedding_3_small
        ADD COLUMN exchange_id INTEGER
      SQL
    end

    # Check if updated_at column exists
    result = conn.query(<<~SQL)
      SELECT COUNT(*) FROM information_schema.columns
      WHERE table_name = 'text_embedding_3_small' AND column_name = 'updated_at'
    SQL
    has_updated_at = result.to_a.first[0].positive?

    # Add updated_at column if it doesn't exist
    unless has_updated_at
      conn.query(<<~SQL)
        ALTER TABLE text_embedding_3_small
        ADD COLUMN updated_at TIMESTAMP
      SQL
    end

    # Set default value for updated_at on existing rows
    conn.query(<<~SQL)
      UPDATE text_embedding_3_small
      SET updated_at = indexed_at
      WHERE updated_at IS NULL
    SQL

    # Add indexes for foreign key lookups and filtering
    # Note: DuckDB doesn't support partial indexes, so we rely on application-level
    # upsert logic to enforce uniqueness for (kind, conversation_id) and (kind, exchange_id)

    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_embedding_conversation
      ON text_embedding_3_small(conversation_id)
    SQL

    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_embedding_exchange
      ON text_embedding_3_small(exchange_id)
    SQL

    # Composite index for efficient lookups by kind and conversation
    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_embedding_kind_conversation
      ON text_embedding_3_small(kind, conversation_id)
    SQL

    # Composite index for efficient lookups by kind and exchange
    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_embedding_kind_exchange
      ON text_embedding_3_small(kind, exchange_id)
    SQL
  end
}
