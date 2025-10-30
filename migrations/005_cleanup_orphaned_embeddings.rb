# frozen_string_literal: true

# Migration: Clean up orphaned embeddings (no conversation_id or exchange_id)
{
  version: 5,
  name: "cleanup_orphaned_embeddings",
  up: lambda do |conn|
    # Delete conversation embeddings that don't have a conversation_id
    result = conn.query(<<~SQL)
      SELECT COUNT(*) FROM text_embedding_3_small
      WHERE kind = 'conversation_summary' AND conversation_id IS NULL
    SQL
    orphaned_conv_count = result.to_a.first[0]

    if orphaned_conv_count.positive?
      conn.query(<<~SQL)
        DELETE FROM text_embedding_3_small
        WHERE kind = 'conversation_summary' AND conversation_id IS NULL
      SQL
      puts "Migration 005: Deleted #{orphaned_conv_count} orphaned conversation embeddings"
    end

    # Delete exchange embeddings that don't have an exchange_id
    result = conn.query(<<~SQL)
      SELECT COUNT(*) FROM text_embedding_3_small
      WHERE kind = 'exchange_summary' AND exchange_id IS NULL
    SQL
    orphaned_exch_count = result.to_a.first[0]

    if orphaned_exch_count.positive?
      conn.query(<<~SQL)
        DELETE FROM text_embedding_3_small
        WHERE kind = 'exchange_summary' AND exchange_id IS NULL
      SQL
      puts "Migration 005: Deleted #{orphaned_exch_count} orphaned exchange embeddings"
    end

    if orphaned_conv_count.zero? && orphaned_exch_count.zero?
      puts "Migration 005: No orphaned embeddings found"
    else
      puts "Migration 005: Workers will regenerate embeddings within 10 seconds"
    end
  end
}
