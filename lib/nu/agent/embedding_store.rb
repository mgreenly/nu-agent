# frozen_string_literal: true

module Nu
  module Agent
    # Manages storage and retrieval of text embeddings for semantic search
    class EmbeddingStore
      def initialize(connection)
        @connection = connection
      end

      # Get all indexed sources for a given kind
      def get_indexed_sources(kind:)
        result = @connection.query(<<~SQL)
          SELECT source FROM text_embedding_3_small WHERE kind = '#{escape_sql(kind)}'
        SQL
        result.map { |row| row[0] }
      end

      # Store embeddings in the database
      def store_embeddings(kind:, records:)
        records.each do |record|
          source = record[:source]
          content = record[:content]
          embedding = record[:embedding]

          # Convert embedding array to DuckDB array format
          embedding_str = "[#{embedding.join(', ')}]"

          @connection.query(<<~SQL)
            INSERT INTO text_embedding_3_small (kind, source, content, embedding)
            VALUES ('#{escape_sql(kind)}', '#{escape_sql(source)}', '#{escape_sql(content)}', #{embedding_str})
            ON CONFLICT (kind, source) DO NOTHING
          SQL
        end
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

      private

      def escape_sql(string)
        string.to_s.gsub("'", "''")
      end
    end
  end
end
