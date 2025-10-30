# frozen_string_literal: true

module Nu
  module Agent
    # Manages storage and retrieval of text embeddings for semantic search
    class EmbeddingStore
      def initialize(connection, config_store: nil)
        @connection = connection
        @config_store = config_store || ConfigStore.new(connection)
      end

      # Get all indexed sources for a given kind
      # Returns conversation_id or exchange_id depending on the kind
      def get_indexed_sources(kind:)
        # Determine which ID column to use based on kind
        id_column = kind.include?("conversation") ? "conversation_id" : "exchange_id"

        result = @connection.query(<<~SQL)
          SELECT #{id_column} FROM text_embedding_3_small
          WHERE kind = '#{escape_sql(kind)}' AND #{id_column} IS NOT NULL
        SQL
        result.map { |row| row[0] }
      end

      # Store embeddings in the database (DEPRECATED - use upsert_conversation_embedding or upsert_exchange_embedding)
      # This method is kept for backward compatibility but will raise an error
      def store_embeddings(kind:, records:)
        raise NotImplementedError,
              "store_embeddings is deprecated. Use upsert_conversation_embedding or upsert_exchange_embedding instead."
      end

      # Get embedding statistics
      def embedding_stats(kind: nil)
        where_clause = kind ? "WHERE kind = '#{escape_sql(kind)}'" : ""

        result = @connection.query(<<~SQL)
          SELECT kind, COUNT(*) as count
          FROM text_embedding_3_small
          #{where_clause}
          GROUP BY kind
        SQL

        result.map do |row|
          { "kind" => row[0], "count" => row[1] }
        end
      end

      # Clear all embeddings for a given kind
      def clear_embeddings(kind:)
        @connection.query(<<~SQL)
          DELETE FROM text_embedding_3_small WHERE kind = '#{escape_sql(kind)}'
        SQL
      end

      # Upsert conversation embedding (delete + insert pattern for uniqueness)
      def upsert_conversation_embedding(conversation_id:, content:, embedding:)
        kind = "conversation_summary"
        embedding_str = "[#{embedding.join(', ')}]"

        # Delete existing embedding for this conversation
        @connection.query(<<~SQL)
          DELETE FROM text_embedding_3_small
          WHERE kind = '#{escape_sql(kind)}' AND conversation_id = #{conversation_id.to_i}
        SQL

        # Insert new embedding
        @connection.query(<<~SQL)
          INSERT INTO text_embedding_3_small (kind, content, embedding, conversation_id, updated_at)
          VALUES (
            '#{escape_sql(kind)}',
            '#{escape_sql(content)}',
            #{embedding_str},
            #{conversation_id.to_i},
            CURRENT_TIMESTAMP
          )
        SQL
      end

      # Upsert exchange embedding (delete + insert pattern for uniqueness)
      def upsert_exchange_embedding(exchange_id:, content:, embedding:)
        kind = "exchange_summary"
        embedding_str = "[#{embedding.join(', ')}]"

        # Delete existing embedding for this exchange
        @connection.query(<<~SQL)
          DELETE FROM text_embedding_3_small
          WHERE kind = '#{escape_sql(kind)}' AND exchange_id = #{exchange_id.to_i}
        SQL

        # Insert new embedding
        @connection.query(<<~SQL)
          INSERT INTO text_embedding_3_small (kind, content, embedding, exchange_id, updated_at)
          VALUES (
            '#{escape_sql(kind)}',
            '#{escape_sql(content)}',
            #{embedding_str},
            #{exchange_id.to_i},
            CURRENT_TIMESTAMP
          )
        SQL
      end

      # Search for similar embeddings using VSS or linear scan fallback
      def search_similar(kind:, query_embedding:, limit: 10, min_similarity: nil)
        embedding_str = "[#{query_embedding.join(', ')}]::FLOAT[#{query_embedding.length}]"

        if vss_available?
          search_with_vss(kind, embedding_str, limit, min_similarity)
        else
          search_with_linear_scan(kind, embedding_str, limit, min_similarity)
        end
      end

      # Check if VSS extension is available
      def vss_available?
        @config_store.get_bool("vss_available", default: false)
      end

      # Search for similar conversation summaries
      # Returns array of hashes with keys: conversation_id, content, similarity, created_at
      def search_conversations(query_embedding:, limit:, min_similarity:, exclude_conversation_id: nil)
        embedding_str = build_embedding_str(query_embedding)
        similarity_expr = build_similarity_expr(embedding_str)

        result = @connection.query(<<~SQL)
          SELECT
            e.conversation_id,
            e.content,
            #{similarity_expr} AS similarity,
            c.created_at
          FROM text_embedding_3_small e
          INNER JOIN conversations c ON e.conversation_id = c.id
          WHERE e.kind = 'conversation_summary'
            AND e.conversation_id IS NOT NULL
            #{build_conversation_exclusion(exclude_conversation_id)}
            #{build_min_similarity_clause(similarity_expr, min_similarity)}
          ORDER BY similarity DESC
          LIMIT #{limit.to_i}
        SQL

        map_conversation_results(result)
      end

      # Search for similar exchange summaries
      # Returns array of hashes with keys: exchange_id, conversation_id, content, similarity, started_at
      def search_exchanges(query_embedding:, limit:, min_similarity:, conversation_ids: nil)
        embedding_str = build_embedding_str(query_embedding)
        similarity_expr = build_similarity_expr(embedding_str)

        result = @connection.query(<<~SQL)
          SELECT
            e.exchange_id,
            ex.conversation_id,
            e.content,
            #{similarity_expr} AS similarity,
            ex.started_at
          FROM text_embedding_3_small e
          INNER JOIN exchanges ex ON e.exchange_id = ex.id
          WHERE e.kind = 'exchange_summary'
            AND e.exchange_id IS NOT NULL
            #{build_conversation_filter(conversation_ids)}
            #{build_min_similarity_clause(similarity_expr, min_similarity)}
          ORDER BY similarity DESC
          LIMIT #{limit.to_i}
        SQL

        map_exchange_results(result)
      end

      private

      # Helper methods for search queries

      def build_embedding_str(query_embedding)
        "[#{query_embedding.join(', ')}]::FLOAT[#{query_embedding.length}]"
      end

      def build_similarity_expr(embedding_str)
        if vss_available?
          "(1.0 - array_cosine_distance(e.embedding, #{embedding_str}))"
        else
          "array_cosine_similarity(e.embedding, #{embedding_str})"
        end
      end

      def build_min_similarity_clause(similarity_expr, min_similarity)
        return "" unless min_similarity

        "AND #{similarity_expr} >= #{min_similarity.to_f}"
      end

      def build_conversation_exclusion(exclude_conversation_id)
        return "" unless exclude_conversation_id

        "AND e.conversation_id != #{exclude_conversation_id.to_i}"
      end

      def build_conversation_filter(conversation_ids)
        return "" unless conversation_ids && !conversation_ids.empty?

        ids_str = conversation_ids.map(&:to_i).join(", ")
        "AND ex.conversation_id IN (#{ids_str})"
      end

      def map_conversation_results(result)
        result.map do |row|
          {
            conversation_id: row[0],
            content: row[1],
            similarity: row[2].to_f,
            created_at: row[3]
          }
        end
      end

      def map_exchange_results(result)
        result.map do |row|
          {
            exchange_id: row[0],
            conversation_id: row[1],
            content: row[2],
            similarity: row[3].to_f,
            started_at: row[4]
          }
        end
      end

      # Original search helper methods

      def search_with_vss(kind, embedding_str, limit, min_similarity)
        # Determine which ID column to use based on kind
        id_column = kind.include?("conversation") ? "conversation_id" : "exchange_id"

        # Use VSS with cosine distance (lower is better, so we use 1 - distance to get similarity)
        similarity_clause = if min_similarity
                              "AND (1.0 - array_cosine_distance(embedding, #{embedding_str})) >= #{min_similarity.to_f}"
                            else
                              ""
                            end

        result = @connection.query(<<~SQL)
          SELECT
            #{id_column},
            content,
            (1.0 - array_cosine_distance(embedding, #{embedding_str})) AS similarity
          FROM text_embedding_3_small
          WHERE kind = '#{escape_sql(kind)}' AND #{id_column} IS NOT NULL
            #{similarity_clause}
          ORDER BY array_cosine_distance(embedding, #{embedding_str}) ASC
          LIMIT #{limit.to_i}
        SQL

        result.map do |row|
          {
            source_id: row[0],
            content: row[1],
            similarity: row[2].to_f
          }
        end
      end

      def search_with_linear_scan(kind, embedding_str, limit, min_similarity)
        # Determine which ID column to use based on kind
        id_column = kind.include?("conversation") ? "conversation_id" : "exchange_id"

        # Linear scan fallback using array_cosine_similarity
        # First get a reasonable subset to avoid scanning everything
        prefilter_limit = [limit * 10, 1000].min

        result = @connection.query(<<~SQL)
          SELECT
            #{id_column},
            content,
            array_cosine_similarity(embedding, #{embedding_str}) AS similarity
          FROM text_embedding_3_small
          WHERE kind = '#{escape_sql(kind)}' AND #{id_column} IS NOT NULL
          ORDER BY indexed_at DESC
          LIMIT #{prefilter_limit}
        SQL

        # Apply similarity threshold and sort
        results = result.map do |row|
          {
            source_id: row[0],
            content: row[1],
            similarity: row[2].to_f
          }
        end

        # Filter by min_similarity if specified
        results = results.select { |r| r[:similarity] >= min_similarity } if min_similarity

        # Sort by similarity (highest first) and limit
        results.sort_by { |r| -r[:similarity] }.take(limit)
      end

      def escape_sql(string)
        string.to_s.gsub("'", "''")
      end
    end
  end
end
