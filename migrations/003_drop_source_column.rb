# frozen_string_literal: true

# Migration: Drop source column since we now use conversation_id/exchange_id for identification
{
  version: 3,
  name: "drop_source_column",
  up: lambda do |conn|
    # Check if source column exists - if not, migration already applied
    result = conn.query(<<~SQL)
      SELECT COUNT(*) FROM information_schema.columns
      WHERE table_name = 'text_embedding_3_small' AND column_name = 'source'
    SQL
    has_source = result.to_a.first[0].positive?

    return unless has_source # Skip if already migrated

    # DuckDB doesn't support dropping columns directly, so we need to:
    # 1. Check which columns exist (exchange_id and updated_at added in migration 001)
    # 2. Create a new table without the source column
    # 3. Copy data over (excluding source)
    # 4. Drop old table
    # 5. Rename new table

    # Check if exchange_id exists (added in migration 001)
    result = conn.query(<<~SQL)
      SELECT COUNT(*) FROM information_schema.columns
      WHERE table_name = 'text_embedding_3_small' AND column_name = 'exchange_id'
    SQL
    has_exchange_id = result.to_a.first[0].positive?

    # Check if updated_at exists (added in migration 001)
    result = conn.query(<<~SQL)
      SELECT COUNT(*) FROM information_schema.columns
      WHERE table_name = 'text_embedding_3_small' AND column_name = 'updated_at'
    SQL
    has_updated_at = result.to_a.first[0].positive?

    # Create new table without source column
    conn.query(<<~SQL)
      CREATE TABLE text_embedding_3_small_new (
        id INTEGER PRIMARY KEY DEFAULT nextval('text_embedding_3_small_id_seq'),
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        embedding FLOAT[1536],
        indexed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        conversation_id INTEGER,
        exchange_id INTEGER,
        updated_at TIMESTAMP
      )
    SQL

    # Build column list based on what exists
    columns = %w[id kind content embedding indexed_at conversation_id]
    columns << "exchange_id" if has_exchange_id
    columns << "updated_at" if has_updated_at

    # Copy all data from old table to new (excluding source)
    conn.query(<<~SQL)
      INSERT INTO text_embedding_3_small_new (#{columns.join(', ')})
      SELECT #{columns.join(', ')}
      FROM text_embedding_3_small
    SQL

    # Drop old table
    conn.query(<<~SQL)
      DROP TABLE text_embedding_3_small
    SQL

    # Rename new table to original name
    conn.query(<<~SQL)
      ALTER TABLE text_embedding_3_small_new RENAME TO text_embedding_3_small
    SQL

    # Recreate indexes
    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_embedding_conversation
      ON text_embedding_3_small(conversation_id)
    SQL

    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_embedding_exchange
      ON text_embedding_3_small(exchange_id)
    SQL

    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_embedding_kind_conversation
      ON text_embedding_3_small(kind, conversation_id)
    SQL

    conn.query(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_embedding_kind_exchange
      ON text_embedding_3_small(kind, exchange_id)
    SQL

    # NOTE: We rely on application-level upsert logic (DELETE + INSERT)
    # to enforce uniqueness for (kind, conversation_id) and (kind, exchange_id)
  end
}
