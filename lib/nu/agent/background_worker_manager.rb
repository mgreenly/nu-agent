# frozen_string_literal: true

module Nu
  module Agent
    class BackgroundWorkerManager
      attr_reader :summarizer_status, :man_indexer_status, :active_threads

      def initialize(application:, history:, summarizer:, conversation_id:, status_mutex:)
        @application = application
        @history = history
        @summarizer = summarizer
        @conversation_id = conversation_id
        @status_mutex = status_mutex
        @operation_mutex = Mutex.new
        @active_threads = []

        @summarizer_status = build_summarizer_status
        @man_indexer_status = build_man_indexer_status
      end

      def start_summarization_worker
        @operation_mutex.synchronize do
          summarizer_worker = ConversationSummarizer.new(
            history: @history,
            summarizer: @summarizer,
            application: @application,
            status_info: { status: @summarizer_status, mutex: @status_mutex },
            current_conversation_id: @conversation_id
          )

          thread = summarizer_worker.start_worker
          @active_threads << thread
        end
      end

      def start_man_indexer_worker
        @operation_mutex.synchronize do
          begin
            embeddings_client = Clients::OpenAIEmbeddings.new
          rescue StandardError => e
            @application.output_line("[Man Indexer] ERROR: Failed to create OpenAI Embeddings client", type: :error)
            @application.output_line("  #{e.message}", type: :error)
            @application.output_line("Man page indexing requires OpenAI embeddings API access.", type: :error)
            msg = "Please ensure your OpenAI API key has access to text-embedding-3-small."
            @application.output_line(msg, type: :error)
            @status_mutex.synchronize { @man_indexer_status["running"] = false }
            return
          end

          indexer = ManPageIndexer.new(
            history: @history,
            embeddings_client: embeddings_client,
            application: @application,
            status: @man_indexer_status,
            status_mutex: @status_mutex
          )

          thread = indexer.start_worker
          @active_threads << thread
        end
      end

      private

      def build_summarizer_status
        {
          "running" => false,
          "total" => 0,
          "completed" => 0,
          "failed" => 0,
          "current_conversation_id" => nil,
          "last_summary" => nil,
          "spend" => 0.0
        }
      end

      def build_man_indexer_status
        {
          "running" => false,
          "total" => 0,
          "completed" => 0,
          "failed" => 0,
          "skipped" => 0,
          "current_batch" => nil,
          "session_spend" => 0.0,
          "session_tokens" => 0
        }
      end
    end
  end
end
