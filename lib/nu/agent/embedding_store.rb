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
        raise NotImplementedError, "store_embeddings is deprecated. Use upsert_conversation_embedding or upsert_exchange_embedding instead."
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

      private

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
