# frozen_string_literal: true

module Nu
  module Agent
    module RAG
      # Orchestrates the RAG retrieval pipeline using Chain of Responsibility pattern
      # Builds a processor chain and executes it to retrieve relevant context
      class RAGRetriever
        attr_reader :embedding_store, :embedding_client, :config_store

        def initialize(embedding_store:, embedding_client:, config_store:)
          @embedding_store = embedding_store
          @embedding_client = embedding_client
          @config_store = config_store
        end

        # Retrieve relevant context for a query
        # Returns a RAGContext object with formatted_context and metadata
        def retrieve(query:, current_conversation_id: nil)
          # Build processor chain
          chain = build_processor_chain

          # Create context
          context = RAGContext.new(
            query: query,
            current_conversation_id: current_conversation_id
          )

          # Execute pipeline
          chain.process(context)

          # Finalize metadata
          context.finalize

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
      end
    end
  end
end
