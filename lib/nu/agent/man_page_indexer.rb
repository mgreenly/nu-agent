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
        man_indexer = create_man_indexer

        loop do
          break if should_stop_indexing?

          pages_info = get_pages_to_index(man_indexer)
          update_initial_status(pages_info)

          break if indexing_complete?(pages_info[:to_index])

          batch = pages_info[:to_index].take(10)
          update_batch_status(batch)

          records = extract_batch_descriptions(batch, man_indexer)

          next if skip_empty_batch?(records)
          break if @application.instance_variable_get(:@shutdown)

          process_batch(records, man_indexer)
          sleep(6) unless @application.instance_variable_get(:@shutdown)
        end

        mark_indexing_complete
      end

      private

      def create_man_indexer
        ManIndexer.new(
          history: @history,
          embeddings_client: @embeddings_client,
          application: @application
        )
      end

      def should_stop_indexing?
        return true if @application.instance_variable_get(:@shutdown)

        @history.get_config("index_man_enabled") != "true"
      end

      def get_pages_to_index(man_indexer)
        all_man_pages = man_indexer.all_man_pages
        indexed = @history.get_indexed_sources(kind: "man_page")
        to_index = all_man_pages - indexed

        {
          all: all_man_pages,
          indexed: indexed,
          to_index: to_index
        }
      end

      def update_initial_status(pages_info)
        @status_mutex.synchronize do
          @status["running"] = true
          @status["total"] = pages_info[:all].length
          @status["completed"] = pages_info[:indexed].length
        end
      end

      def indexing_complete?(to_index)
        return false unless to_index.empty?

        @status_mutex.synchronize do
          @status["running"] = false
        end
        true
      end

      def update_batch_status(batch)
        @status_mutex.synchronize do
          @status["current_batch"] = batch
        end
      end

      def extract_batch_descriptions(batch, man_indexer)
        records = []
        batch.each do |source|
          break if @application.instance_variable_get(:@shutdown)

          description = man_indexer.extract_description(source)

          if description.nil? || description.empty?
            @status_mutex.synchronize { @status["skipped"] += 1 }
            next
          end

          records << { source: source, content: description }
        end
        records
      end

      def skip_empty_batch?(records)
        return false unless records.empty?

        sleep(1)
        true
      end

      def mark_indexing_complete
        @status_mutex.synchronize do
          @status["running"] = false
          @status["current_batch"] = nil
        end
      end

      def process_batch(records, _man_indexer)
        contents = records.map { |r| r[:content] }
        response = @embeddings_client.generate_embedding(contents)

        return handle_api_error(response, records) if response["error"]

        attach_embeddings_to_records(records, response["embeddings"])
        store_embeddings_in_db(records)
        update_completion_status(records.length, response)
      rescue StandardError => e
        handle_batch_error(e, records)
      end

      def attach_embeddings_to_records(records, embeddings)
        records.each_with_index do |record, i|
          record[:embedding] = embeddings[i]
        end
      end

      def store_embeddings_in_db(records)
        @application.send(:enter_critical_section)
        begin
          @history.store_embeddings(kind: "man_page", records: records)
        ensure
          @application.send(:exit_critical_section)
        end
      end

      def update_completion_status(records_count, response)
        @status_mutex.synchronize do
          @status["completed"] += records_count
          @status["session_spend"] += response["spend"] || 0.0
          @status["session_tokens"] += response["tokens"] || 0
        end
      end

      def handle_batch_error(error, records)
        @status_mutex.synchronize do
          @status["failed"] += records.length
        end

        @application.output_line("[Man Indexer] Error processing batch: #{error.class}: #{error.message}", type: :debug)
        return unless @application.instance_variable_get(:@debug)

        error.backtrace.first(5).each do |line|
          @application.output_line("  #{line}", type: :debug)
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
