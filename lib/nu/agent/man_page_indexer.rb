# frozen_string_literal: true

module Nu
  module Agent
    # Manages background man page indexing worker thread
    class ManPageIndexer
      def initialize(history:, embeddings_client:, application:, status:, status_mutex:)
        @history = history
        @embeddings_client = embeddings_client
        @application = application
        @status = status
        @status_mutex = status_mutex
      end

      # Start the background worker thread
      def start_worker
        Thread.new do
          index_pages
        rescue StandardError => e
          @application.output_line("[Man Indexer] Worker thread error: #{e.class}: #{e.message}", type: :error)
          if @application.instance_variable_get(:@debug)
            e.backtrace.first(10).each do |line|
              @application.output_line("  #{line}", type: :debug)
            end
          end
          @status_mutex.synchronize do
            @status["running"] = false
          end
        end
      end

      # Main indexing loop - processes man pages in batches
      def index_pages
        # Create man indexer with application for debug messages
        man_indexer = ManIndexer.new(
          history: @history,
          embeddings_client: @embeddings_client,
          application: @application
        )

        loop do
          # Check for shutdown or disabled
          break if @application.instance_variable_get(:@shutdown)
          break unless @history.get_config("index_man_enabled") == "true"

          # Get all man pages from system
          all_man_pages = man_indexer.all_man_pages

          # Get already indexed man pages from DB
          indexed = @history.get_indexed_sources(kind: "man_page")

          # Calculate exclusive set (not yet indexed)
          to_index = all_man_pages - indexed

          # Update total count
          @status_mutex.synchronize do
            @status["running"] = true
            @status["total"] = all_man_pages.length
            @status["completed"] = indexed.length
          end

          # Break if nothing left to index
          if to_index.empty?
            @status_mutex.synchronize do
              @status["running"] = false
            end
            break
          end

          # Process in batches of 10
          batch = to_index.take(10)

          # Update current batch
          @status_mutex.synchronize do
            @status["current_batch"] = batch
          end

          # Extract DESCRIPTION sections
          records = []
          batch.each do |source|
            # Check for shutdown before processing each man page
            break if @application.instance_variable_get(:@shutdown)

            description = man_indexer.extract_description(source)

            if description.nil? || description.empty?
              # Skip this man page
              @status_mutex.synchronize do
                @status["skipped"] += 1
              end
              next
            end

            records << {
              source: source,
              content: description
            }
          end

          # Skip API call if no valid descriptions
          if records.empty?
            sleep(1)
            next
          end

          # Check for shutdown before expensive API call
          break if @application.instance_variable_get(:@shutdown)

          # Call OpenAI embeddings API (batch request)
          process_batch(records, man_indexer)

          # Rate limiting: sleep to maintain 10 req/min (6 seconds between requests)
          sleep(6) unless @application.instance_variable_get(:@shutdown)
        end

        # Mark as complete
        @status_mutex.synchronize do
          @status["running"] = false
          @status["current_batch"] = nil
        end
      end

      private

      def process_batch(records, _man_indexer)
        contents = records.map { |r| r[:content] }
        response = @embeddings_client.generate_embedding(contents)

        # Check for errors
        if response["error"]
          handle_api_error(response, records)
          return
        end

        # Get embeddings and add to records
        embeddings = response["embeddings"]
        records.each_with_index do |record, i|
          record[:embedding] = embeddings[i]
        end

        # Store in database
        @application.send(:enter_critical_section)
        begin
          @history.store_embeddings(kind: "man_page", records: records)
        ensure
          @application.send(:exit_critical_section)
        end

        # Update status
        @status_mutex.synchronize do
          @status["completed"] += records.length
          @status["session_spend"] += response["spend"] || 0.0
          @status["session_tokens"] += response["tokens"] || 0
        end
      rescue StandardError => e
        # On error, mark batch as failed and log the error
        @status_mutex.synchronize do
          @status["failed"] += records.length
        end

        # Log error using thread-safe output
        @application.output_line("[Man Indexer] Error processing batch: #{e.class}: #{e.message}", type: :debug)
        if @application.instance_variable_get(:@debug)
          e.backtrace.first(5).each do |line|
            @application.output_line("  #{line}", type: :debug)
          end
        end
      end

      def handle_api_error(response, records)
        error_body = response["error"]["body"]
        if error_body && error_body["error"]
          error_msg = error_body["error"]["message"]
          error_code = error_body["error"]["code"]

          # Check for model access issues
          if error_code == "model_not_found" && error_msg.include?("text-embedding-3-small")
            @application.output_line(
              "[Man Indexer] ERROR: OpenAI API key does not have access to text-embedding-3-small",
              type: :error
            )
            @application.output_line("  Please enable embeddings API access in your OpenAI project settings",
                                     type: :error)
            @application.output_line("  Visit: https://platform.openai.com/settings", type: :error)

            # Stop indexing - no point continuing
            @status_mutex.synchronize { @status["running"] = false }
            return :stop
          else
            @application.output_line("[Man Indexer] API Error: #{error_msg}", type: :debug)
          end
        end

        @status_mutex.synchronize do
          @status["failed"] += records.length
        end
        sleep(6) # Rate limiting
        nil
      end
    end
  end
end
