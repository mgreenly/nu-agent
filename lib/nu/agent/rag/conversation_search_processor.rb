# frozen_string_literal: true

module Nu
  module Agent
    module RAG
      # Searches for similar conversation summaries using VSS or linear scan
      # Excludes current conversation and applies min_similarity threshold
      class ConversationSearchProcessor < RAGProcessor
        def initialize(embedding_store:, config_store:)
          super()
          @embedding_store = embedding_store
          @config_store = config_store
        end

        protected

        def process_internal(context)
          return unless context.query_embedding

          # Get configuration
          limit = @config_store.get_int("rag_conversation_limit", default: 5)
          min_similarity = @config_store.get_float("rag_conversation_min_similarity", default: 0.7)

          # Search for similar conversations
          results = @embedding_store.search_conversations(
            query_embedding: context.query_embedding,
            limit: limit,
            min_similarity: min_similarity,
            exclude_conversation_id: context.current_conversation_id,
            after_date: context.after_date,
            before_date: context.before_date
          )

          # Store results in context
          context.conversations = results
          context.metadata[:conversation_count] = results.length
        end
      end
    end
  end
end
