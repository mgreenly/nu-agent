# frozen_string_literal: true

module Nu
  module Agent
    module Workers
      # Manages background embedding generation for conversation and exchange summaries
      class EmbeddingGenerator < PausableTask
        def initialize(options)
          # Initialize PausableTask with shutdown flag from application
          super(status_info: options[:status_info], shutdown_flag: options[:application])

          @history = options[:history]
          @embedding_client = options[:embedding_client]
          @application = options[:application]
          @current_conversation_id = options[:current_conversation_id]
          @config_store = options[:config_store]
        end

        def load_verbosity
          @config_store.get_int("embeddings_verbosity", default: 0)
        end

        # Output debug message if verbosity level is sufficient
        def debug_output(message, level: 0)
          return unless @application.debug && level <= load_verbosity

          @application.output_line("[EmbeddingGenerator] #{message}", type: :debug)
        end

        # Main processing loop - generates embeddings for conversations and exchanges
        def process_embeddings
          return unless @application.embedding_enabled

          conversations, exchanges, queue = discover_work

          if queue.empty?
            debug_output("No work found (no summaries need embeddings)", level: 3)
            return
          end

          start_time = log_start(conversations, exchanges, queue)
          initialize_status(queue)
          process_queue_in_batches(queue)
          log_completion(start_time)
        end

        protected

        # Called by PausableTask in the worker loop
        def do_work
          process_embeddings
        end

        # Override shutdown check to use application's shutdown flag
        def shutdown_requested?
          @application.instance_variable_get(:@shutdown)
        end

        private

        def discover_work
          conversations = @history.get_conversations_needing_embeddings(exclude_id: @current_conversation_id)
          exchanges = @history.get_exchanges_needing_embeddings(exclude_conversation_id: @current_conversation_id)
          queue = build_queue(conversations, exchanges)
          [conversations, exchanges, queue]
        end

        def log_start(conversations, exchanges, queue)
          conv_ids = conversations.map { |c| c["id"] }.join(", ")
          exch_ids = exchanges.map { |e| e["id"] }.join(", ")
          ids_display = build_ids_display(conv_ids, exch_ids)
          debug_output("Started, found #{queue.length} items to embed (#{ids_display.join(', ')})", level: 0)
          Time.now
        end

        def build_ids_display(conv_ids, exch_ids)
          ids = []
          ids << "conversations: #{conv_ids}" unless conv_ids.empty?
          ids << "exchanges: #{exch_ids}" unless exch_ids.empty?
          ids
        end

        def initialize_status(queue)
          @status_mutex.synchronize do
            @status["running"] = true
            @status["total"] = queue.length
            @status["completed"] = 0
            @status["failed"] = 0
          end
        end

        def process_queue_in_batches(queue)
          batch_size = @config_store.get_int("embedding_batch_size", default: 10)
          queue.each_slice(batch_size) do |batch|
            break if shutdown_requested?

            process_batch(batch)
            apply_rate_limiting
          end
        end

        def apply_rate_limiting
          rate_limit_ms = @config_store.get_int("embedding_rate_limit_ms", default: 100)
          sleep(rate_limit_ms / 1000.0) if rate_limit_ms.positive? && !shutdown_requested?
        end

        def log_completion(start_time)
          completed, failed = finalize_status
          duration = Time.now - start_time
          debug_output("Completed (#{completed} succeeded, #{failed} failed) in #{duration.round(1)}s", level: 0)
        end

        def finalize_status
          completed = nil
          failed = nil
          @status_mutex.synchronize do
            @status["running"] = false
            @status["current_item"] = nil
            completed = @status["completed"]
            failed = @status["failed"]
          end
          [completed, failed]
        end

        def build_queue(conversations, exchanges)
          # Add conversations with explicit type discriminator
          queue = conversations.map do |conv|
            {
              type: "conversation",
              id: conv["id"],
              content: conv["summary"]
            }
          end

          # Add exchanges with explicit type discriminator
          exchanges.each do |exchange|
            queue << {
              type: "exchange",
              id: exchange["id"],
              content: exchange["summary"]
            }
          end

          queue
        end

        def process_batch(batch)
          texts = batch.map { |item| item[:content] }
          return if texts.empty?

          debug_output("Processing batch of #{batch.length} items", level: 1)

          response = generate_embeddings_with_retry(texts)
          return if shutdown_requested? || response.nil?

          if response["error"]
            handle_batch_error(response, batch)
            return
          end

          process_batch_items(batch, response)
          update_spend(response)
        end

        def handle_batch_error(response, batch)
          error_info = response["error"]
          debug_output("API error for batch of #{batch.length} items - #{error_info}", level: 0)
          @status_mutex.synchronize { @status["failed"] += batch.length }
        end

        def process_batch_items(batch, response)
          batch.each_with_index do |item, index|
            break if shutdown_requested?

            embedding = response["embeddings"][index]
            next unless embedding

            process_item(item, embedding, response)
          end
        end

        def update_spend(response)
          cost = response["spend"] || 0.0
          @status_mutex.synchronize { @status["spend"] += cost }
        end

        def process_item(item, embedding, _response)
          update_status_current_item(item)

          debug_output("Processing #{item[:type]}:#{item[:id]}", level: 2)

          begin
            @application.send(:enter_critical_section)
            store_embedding(item, embedding)
            debug_output("Stored embedding for #{item[:type]}:#{item[:id]}", level: 3)
            increment_completed_count
          rescue StandardError => e
            handle_item_error(item, e)
          ensure
            @application.send(:exit_critical_section)
          end
        end

        def store_embedding(item, embedding)
          case item[:type]
          when "conversation"
            @history.upsert_conversation_embedding(
              conversation_id: item[:id],
              content: item[:content],
              embedding: embedding
            )
          when "exchange"
            @history.upsert_exchange_embedding(
              exchange_id: item[:id],
              content: item[:content],
              embedding: embedding
            )
          end
        end

        def handle_item_error(item, error)
          debug_output("Failed to process #{item[:type]}:#{item[:id]} - #{error.class}: #{error.message}", level: 0)
          increment_failed_count
        end

        def generate_embeddings_with_retry(texts, attempt: 1)
          response = call_embedding_api_with_shutdown_check(texts)
          retry_on_error(texts, attempt, response)
        end

        def call_embedding_api_with_shutdown_check(texts)
          api_thread = Thread.new do
            Thread.current.report_on_exception = false
            @embedding_client.generate_embedding(texts)
          end

          wait_for_api_response(api_thread)
        end

        def wait_for_api_response(api_thread)
          response = nil
          loop do
            if api_thread.join(0.1)
              response = api_thread.value
              break
            end
            break if shutdown_requested?
          end
          response
        end

        def retry_on_error(texts, attempt, response)
          max_attempts = 3
          return response unless should_retry?(response, attempt, max_attempts)

          sleep_with_backoff(attempt)
          generate_embeddings_with_retry(texts, attempt: attempt + 1)
        end

        def should_retry?(response, attempt, max_attempts)
          response && response["error"] && attempt < max_attempts && !shutdown_requested?
        end

        def sleep_with_backoff(attempt)
          base_delay = 1.0
          delay = base_delay * (2**(attempt - 1))
          jitter = rand * 0.5 * delay
          total_delay = delay + jitter
          sleep(total_delay) unless shutdown_requested?
        end

        def update_status_current_item(item)
          @status_mutex.synchronize do
            @status["current_item"] = "#{item[:type]}:#{item[:id]}"
          end
        end

        def increment_completed_count
          @status_mutex.synchronize { @status["completed"] += 1 }
        end

        def increment_failed_count
          @status_mutex.synchronize { @status["failed"] += 1 }
        end
      end
    end
  end
end
