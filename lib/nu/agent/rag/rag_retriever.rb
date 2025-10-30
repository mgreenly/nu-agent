# frozen_string_literal: true

module Nu
  module Agent
    module RAG
      # Orchestrates the RAG retrieval pipeline using Chain of Responsibility pattern
      # Builds a processor chain and executes it to retrieve relevant context
      class RAGRetriever
        attr_reader :embedding_store, :embedding_client, :config_store, :retrieval_logger, :cache

        def initialize(embedding_store:, embedding_client:, config_store:, retrieval_logger: nil, cache: nil)
          @embedding_store = embedding_store
          @embedding_client = embedding_client
          @config_store = config_store
          @retrieval_logger = retrieval_logger
          @cache = cache
        end

        # Retrieve relevant context for a query
        # Returns a RAGContext object with formatted_context and metadata
        def retrieve(query:, current_conversation_id: nil, after_date: nil, before_date: nil, recency_weight: nil)
          # Try cache if enabled
          if @cache
            # Generate embedding once for both cache key and potential pipeline use
            embedding_response = @embedding_client.generate_embedding(query)
            query_embedding = embedding_response["embeddings"] if embedding_response && !embedding_response["error"]

            if query_embedding
              cache_key = generate_cache_key_from_embedding(query_embedding, current_conversation_id, after_date,
                                                            before_date, recency_weight)
              cached_result = @cache.get(cache_key)

              if cached_result
                # Cache hit - return cached context
                context = restore_context_from_cache(cached_result, query, current_conversation_id,
                                                     after_date, before_date, recency_weight)
                context.query_embedding = query_embedding # Set for logging
                log_retrieval(context, cache_hit: true) if @retrieval_logger
                return context
              end

              # Cache miss - execute pipeline with pre-generated embedding
              context = execute_retrieval_pipeline_with_embedding(query, query_embedding, current_conversation_id,
                                                                  after_date, before_date, recency_weight)
              @cache.set(cache_key, cache_context_data(context))
              log_retrieval(context, cache_hit: false) if @retrieval_logger
              return context
            end
          end

          # Cache disabled or embedding failed - execute normal pipeline
          context = execute_retrieval_pipeline(query, current_conversation_id, after_date, before_date, recency_weight)
          log_retrieval(context, cache_hit: false) if @retrieval_logger
          context
        end

        private

        # Execute the full retrieval pipeline
        def execute_retrieval_pipeline(query, current_conversation_id, after_date, before_date, recency_weight)
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

          context
        end

        # Execute retrieval pipeline with pre-generated embedding (for cache optimization)
        # rubocop:disable Metrics/ParameterLists
        def execute_retrieval_pipeline_with_embedding(query, query_embedding, current_conversation_id,
                                                      after_date, before_date, recency_weight)
          # rubocop:enable Metrics/ParameterLists
          # Create context with pre-generated embedding
          context = RAGContext.new(
            query: query,
            current_conversation_id: current_conversation_id,
            after_date: after_date,
            before_date: before_date,
            recency_weight: recency_weight
          )
          context.query_embedding = query_embedding

          # Build processor chain starting from conversation search (skip query embedding processor)
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

          conversation_processor.next_processor = exchange_processor
          exchange_processor.next_processor = formatter_processor

          # Execute pipeline
          conversation_processor.process(context)

          # Finalize metadata
          context.finalize

          context
        end

        # Generate cache key from embedding and config parameters
        def generate_cache_key_from_embedding(query_embedding, current_conversation_id, after_date, before_date,
                                              recency_weight)
          # Use cache's key generation with config parameters
          config = {
            current_conversation_id: current_conversation_id,
            after_date: after_date,
            before_date: before_date,
            recency_weight: recency_weight
          }

          @cache.generate_cache_key(query_embedding, config)
        end

        # Extract cacheable data from context
        def cache_context_data(context)
          {
            conversations: context.conversations,
            exchanges: context.exchanges,
            formatted_context: context.formatted_context,
            metadata: context.metadata.dup
          }
        end

        # Restore context from cached data
        # rubocop:disable Metrics/ParameterLists
        def restore_context_from_cache(cached_data, query, current_conversation_id, after_date, before_date,
                                       recency_weight)
          # rubocop:enable Metrics/ParameterLists
          context = RAGContext.new(
            query: query,
            current_conversation_id: current_conversation_id,
            after_date: after_date,
            before_date: before_date,
            recency_weight: recency_weight
          )

          context.conversations = cached_data[:conversations]
          context.exchanges = cached_data[:exchanges]
          context.formatted_context = cached_data[:formatted_context]

          # Restore metadata but update timing for this retrieval
          context.metadata.merge!(cached_data[:metadata])
          context.finalize

          context
        end

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

        def log_retrieval(context, cache_hit: false)
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
            cache_hit: cache_hit
          )
        end
      end
    end
  end
end
