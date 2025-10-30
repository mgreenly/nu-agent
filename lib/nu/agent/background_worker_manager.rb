# frozen_string_literal: true

module Nu
  module Agent
    class BackgroundWorkerManager
      attr_reader :summarizer_status, :exchange_summarizer_status, :embedding_status, :active_threads

      def initialize(options)
        @application = options[:application]
        @history = options[:history]
        @summarizer = options[:summarizer]
        @conversation_id = options[:conversation_id]
        @status_mutex = options[:status_mutex]
        @embedding_client = options[:embedding_client]
        @operation_mutex = Mutex.new
        @active_threads = []
        @workers = []

        @summarizer_status = build_summarizer_status
        @exchange_summarizer_status = build_exchange_summarizer_status
        @embedding_status = build_embedding_status
      end

      def start_summarization_worker
        @operation_mutex.synchronize do
          # Start conversation summarizer
          conversation_summarizer = Workers::ConversationSummarizer.new(
            history: @history,
            summarizer: @summarizer,
            application: @application,
            status_info: { status: @summarizer_status, mutex: @status_mutex },
            current_conversation_id: @conversation_id
          )
          @workers << conversation_summarizer

          thread = conversation_summarizer.start_worker
          @active_threads << thread

          # Start exchange summarizer
          exchange_summarizer = Workers::ExchangeSummarizer.new(
            history: @history,
            summarizer: @summarizer,
            application: @application,
            status_info: { status: @exchange_summarizer_status, mutex: @status_mutex },
            current_conversation_id: @conversation_id
          )
          @workers << exchange_summarizer

          thread = exchange_summarizer.start_worker
          @active_threads << thread
        end
      end

      def start_embedding_worker
        return unless @embedding_client

        @operation_mutex.synchronize do
          embedding_worker = Workers::EmbeddingGenerator.new(
            history: @history,
            embedding_client: @embedding_client,
            application: @application,
            status_info: { status: @embedding_status, mutex: @status_mutex },
            current_conversation_id: @conversation_id,
            config_store: @history.instance_variable_get(:@config_store)
          )
          @workers << embedding_worker

          thread = embedding_worker.start_worker
          @active_threads << thread
        end
      end

      # Pause all background workers
      def pause_all
        @operation_mutex.synchronize do
          @workers.each(&:pause)
        end
      end

      # Resume all background workers
      def resume_all
        @operation_mutex.synchronize do
          @workers.each(&:resume)
        end
      end

      # Wait for all workers to pause (with timeout)
      # @param timeout [Numeric] Maximum seconds to wait for all workers to pause
      # @return [Boolean] true if all workers paused within timeout
      def wait_until_all_paused(timeout: 5)
        @workers.all? { |worker| worker.wait_until_paused(timeout: timeout) }
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

      def build_exchange_summarizer_status
        {
          "running" => false,
          "total" => 0,
          "completed" => 0,
          "failed" => 0,
          "current_exchange_id" => nil,
          "last_summary" => nil,
          "spend" => 0.0
        }
      end

      def build_embedding_status
        {
          "running" => false,
          "total" => 0,
          "completed" => 0,
          "failed" => 0,
          "current_item" => nil,
          "spend" => 0.0
        }
      end
    end
  end
end
