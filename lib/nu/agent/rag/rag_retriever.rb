# frozen_string_literal: true

module Nu
  module Agent
    module RAG
      # Orchestrates the RAG retrieval pipeline using Chain of Responsibility pattern
      # Builds a processor chain and executes it to retrieve relevant context
      class RAGRetriever
        attr_reader :embedding_store, :embedding_client, :config_store, :retrieval_logger

        def initialize(embedding_store:, embedding_client:, config_store:, retrieval_logger: nil)
          @embedding_store = embedding_store
          @embedding_client = embedding_client
          @config_store = config_store
          @retrieval_logger = retrieval_logger
        end

        # Retrieve relevant context for a query
        # Returns a RAGContext object with formatted_context and metadata
        def retrieve(query:, current_conversation_id: nil, after_date: nil, before_date: nil, recency_weight: nil)
          # Build processor chain
          chain = build_processor_chain

          # Create context
          context = RAGContext.new(
            query: query,
            current_conversation_id: current_conversation_id,
            after_date: after_date,
            before_date: before_date,
            recency_weight: recency_weight
          )

          # Execute pipeline
          chain.process(context)

          # Finalize metadata
          context.finalize

          # Log retrieval metrics if logger is available
          log_retrieval(context) if @retrieval_logger

          context
        end

        private

        def build_processor_chain
          # Create processors
          query_processor = QueryEmbeddingProcessor.new(
            embedding_client: @embedding_client
          )

          conversation_processor = ConversationSearchProcessor.new(
            embedding_store: @embedding_store,
            config_store: @config_store
          )

          exchange_processor = ExchangeSearchProcessor.new(
            embedding_store: @embedding_store,
            config_store: @config_store
          )

          formatter_processor = ContextFormatterProcessor.new(
            config_store: @config_store
          )

          # Chain processors together
          query_processor.next_processor = conversation_processor
          conversation_processor.next_processor = exchange_processor
          exchange_processor.next_processor = formatter_processor

          # Return the head of the chain
          query_processor
        end

        def log_retrieval(context)
          return unless context.query_embedding

          query_hash = @retrieval_logger.generate_query_hash(context.query_embedding, precision: 3)

          # Extract top scores
          top_conversation_score = context.conversations.first&.fetch(:similarity, nil)
          top_exchange_score = context.exchanges.first&.fetch(:similarity, nil)

          @retrieval_logger.log_retrieval(
            query_hash: query_hash,
            conversation_candidates: context.conversations.size,
            exchange_candidates: context.exchanges.size,
            retrieval_duration_ms: context.metadata[:duration_ms],
            top_conversation_score: top_conversation_score,
            top_exchange_score: top_exchange_score,
            cache_hit: false # Will be updated when cache is implemented
          )
        end
      end
    end
  end
end
