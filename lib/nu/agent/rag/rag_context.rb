# frozen_string_literal: true

module Nu
  module Agent
    module RAG
      # Context object passed through the RAG retrieval pipeline
      # Each processor reads from and writes to this context
      class RAGContext
        attr_accessor :query, :query_embedding, :conversations, :exchanges,
                      :formatted_context, :metadata, :current_conversation_id,
                      :after_date, :before_date, :recency_weight

        def initialize(query:, current_conversation_id: nil, after_date: nil, before_date: nil, recency_weight: nil)
          @query = query
          @current_conversation_id = current_conversation_id
          @after_date = after_date
          @before_date = before_date
          @recency_weight = recency_weight
          @query_embedding = nil
          @conversations = []
          @exchanges = []
          @formatted_context = nil
          @metadata = {
            start_time: Time.now,
            conversation_count: 0,
            exchange_count: 0,
            total_tokens: 0
          }
        end

        # Record the end time and calculate duration
        def finalize
          @metadata[:end_time] = Time.now
          @metadata[:duration_ms] = ((@metadata[:end_time] - @metadata[:start_time]) * 1000).round(2)
        end
      end
    end
  end
end
