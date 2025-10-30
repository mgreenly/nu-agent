# frozen_string_literal: true

module Nu
  module Agent
    module RAG
      # Searches for similar exchange summaries
      # Can search within specific conversations or globally
      # Applies global cap across all exchanges
      class ExchangeSearchProcessor < RAGProcessor
        def initialize(embedding_store:, config_store:)
          super()
          @embedding_store = embedding_store
          @config_store = config_store
        end

        protected

        def process_internal(context)
          return unless context.query_embedding

          # Get configuration
          exchanges_per_conversation = @config_store.get_int("rag_exchanges_per_conversation", default: 3)
          global_exchange_cap = @config_store.get_int("rag_exchange_global_cap", default: 10)
          min_similarity = @config_store.get_float("rag_exchange_min_similarity", default: 0.6)

          # Determine which conversations to search in
          conversation_ids = context.conversations.map { |c| c[:conversation_id] }

          # If no conversations meet the threshold, search globally
          if conversation_ids.empty?
            search_globally(context, global_exchange_cap, min_similarity)
          else
            search_per_conversation(context, conversation_ids, exchanges_per_conversation,
                                    global_exchange_cap, min_similarity)
          end
        end

        private

        def search_globally(context, limit, min_similarity)
          results = @embedding_store.search_exchanges(
            query_embedding: context.query_embedding,
            limit: limit,
            min_similarity: min_similarity,
            conversation_ids: nil,
            after_date: context.after_date,
            before_date: context.before_date
          )

          context.exchanges = results
          context.metadata[:exchange_count] = results.length
        end

        def search_per_conversation(context, conversation_ids, per_conversation, global_cap, min_similarity)
          all_exchanges = []

          # Search within each conversation
          conversation_ids.each do |conv_id|
            exchanges = @embedding_store.search_exchanges(
              query_embedding: context.query_embedding,
              limit: per_conversation,
              min_similarity: min_similarity,
              conversation_ids: [conv_id],
              after_date: context.after_date,
              before_date: context.before_date
            )

            all_exchanges.concat(exchanges)

            # Stop if we've hit the global cap
            break if all_exchanges.length >= global_cap
          end

          # Apply global cap and re-sort by similarity
          context.exchanges = all_exchanges
                              .sort_by { |e| -e[:similarity] }
                              .take(global_cap)
          context.metadata[:exchange_count] = context.exchanges.length
        end
      end
    end
  end
end
