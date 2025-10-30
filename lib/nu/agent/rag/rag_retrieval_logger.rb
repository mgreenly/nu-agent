# frozen_string_literal: true

require "digest"

module Nu
  module Agent
    module RAG
      # Logs RAG retrieval operations for observability and performance monitoring
      class RAGRetrievalLogger
        def initialize(connection)
          @connection = connection
        end

        # Log a retrieval operation with its metrics
        def log_retrieval(data)
          query_hash = data[:query_hash] || raise(ArgumentError, "query_hash is required")
          conversation_candidates = data[:conversation_candidates] || 0
          exchange_candidates = data[:exchange_candidates] || 0
          duration_ms = data[:retrieval_duration_ms]
          raise(ArgumentError, "retrieval_duration_ms is required") unless duration_ms

          top_conversation_score = data[:top_conversation_score]
          top_exchange_score = data[:top_exchange_score]
          filtered_by = data[:filtered_by]
          cache_hit = data[:cache_hit] || false

          @connection.query(<<~SQL)
            INSERT INTO rag_retrieval_logs (
              query_hash,
              conversation_candidates,
              exchange_candidates,
              retrieval_duration_ms,
              top_conversation_score,
              top_exchange_score,
              filtered_by,
              cache_hit,
              timestamp
            ) VALUES (
              '#{escape_sql(query_hash)}',
              #{conversation_candidates.to_i},
              #{exchange_candidates.to_i},
              #{duration_ms.to_i},
              #{top_conversation_score ? top_conversation_score.to_f : 'NULL'},
              #{top_exchange_score ? top_exchange_score.to_f : 'NULL'},
              #{filtered_by ? "'#{escape_sql(filtered_by)}'" : 'NULL'},
              #{cache_hit ? 'TRUE' : 'FALSE'},
              CURRENT_TIMESTAMP
            )
          SQL
        end

        # Generate a consistent hash for a query embedding
        # Uses rounding to group similar queries together for cache key generation
        def generate_query_hash(query_embedding, precision: 3)
          # Round embedding values to specified precision to create cache-friendly hashes
          rounded = query_embedding.map { |v| v.round(precision) }
          Digest::SHA256.hexdigest(rounded.join(","))[0..15]
        end

        # Get recent retrieval logs
        def get_recent_logs(limit: 100)
          result = @connection.query(<<~SQL)
            SELECT
              id, query_hash, timestamp, conversation_candidates,
              exchange_candidates, retrieval_duration_ms, top_conversation_score,
              top_exchange_score, filtered_by, cache_hit
            FROM rag_retrieval_logs
            ORDER BY timestamp DESC
            LIMIT #{limit.to_i}
          SQL

          result.map { |row| map_log_row(row) }
        end

        private

        def escape_sql(string)
          string.to_s.gsub("'", "''")
        end

        def map_log_row(row)
          {
            id: row[0],
            query_hash: row[1],
            timestamp: row[2],
            conversation_candidates: row[3],
            exchange_candidates: row[4],
            retrieval_duration_ms: row[5],
            top_conversation_score: row[6],
            top_exchange_score: row[7],
            filtered_by: row[8],
            cache_hit: row[9]
          }
        end
      end
    end
  end
end
