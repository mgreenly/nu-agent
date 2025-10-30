# frozen_string_literal: true

module Nu
  module Agent
    module RAG
      # Generates embedding for the query text
      # Caches the embedding in the context for downstream processors
      class QueryEmbeddingProcessor < RAGProcessor
        def initialize(embedding_client:)
          super()
          @embedding_client = embedding_client
        end

        protected

        def process_internal(context)
          return if context.query.nil? || context.query.empty?

          # Generate embedding for the query
          response = @embedding_client.generate_embedding(context.query)

          # Handle errors
          return if response["error"]

          # Store the embedding in context
          context.query_embedding = response["embeddings"]
        end
      end
    end
  end
end
