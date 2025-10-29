# frozen_string_literal: true

module Nu
  module Agent
    class BackgroundWorkerManager
      attr_reader :summarizer_status, :active_threads

      def initialize(application:, history:, summarizer:, conversation_id:, status_mutex:)
        @application = application
        @history = history
        @summarizer = summarizer
        @conversation_id = conversation_id
        @status_mutex = status_mutex
        @operation_mutex = Mutex.new
        @active_threads = []

        @summarizer_status = build_summarizer_status
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
    end
  end
end
