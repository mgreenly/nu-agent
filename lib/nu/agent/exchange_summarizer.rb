# frozen_string_literal: true

module Nu
  module Agent
    # Manages background exchange summarization worker thread
    class ExchangeSummarizer
      def initialize(history:, summarizer:, application:, status_info:, current_conversation_id:)
        @history = history
        @summarizer = summarizer
        @application = application
        @status = status_info[:status]
        @status_mutex = status_info[:mutex]
        @current_conversation_id = current_conversation_id
      end

      # Start the background worker thread
      def start_worker
        Thread.new do
          Thread.current.report_on_exception = false
          summarize_exchanges
        rescue StandardError
          @status_mutex.synchronize do
            @status["running"] = false
          end
        end
      end

      # Main summarization loop - processes unsummarized exchanges
      def summarize_exchanges
        # Get exchanges that need summarization
        exchanges = @history.get_unsummarized_exchanges(exclude_conversation_id: @current_conversation_id)

        return if exchanges.empty?

        # Update status
        @status_mutex.synchronize do
          @status["running"] = true
          @status["total"] = exchanges.length
          @status["completed"] = 0
          @status["failed"] = 0
        end

        exchanges.each do |exchange|
          # Check for shutdown signal before processing each exchange
          break if @application.instance_variable_get(:@shutdown)

          process_exchange(exchange)
        end

        # Mark as complete
        @status_mutex.synchronize do
          @status["running"] = false
          @status["current_exchange_id"] = nil
        end
      end

      private

      def process_exchange(exchange)
        exchange_id = exchange["id"]
        conversation_id = exchange["conversation_id"]
        update_status_current_exchange(exchange_id)

        # Get all messages for the conversation (we'll filter by exchange_id)
        messages = @history.messages(conversation_id: conversation_id, include_in_context_only: false)

        # Filter messages for this specific exchange
        exchange_messages = messages.select { |m| m["exchange_id"] == exchange_id }

        return handle_empty_exchange(exchange_id) if exchange_messages.empty?

        summary_prompt = build_summary_prompt(exchange_messages)
        return if shutdown_requested?

        response = make_llm_call_with_shutdown_check(summary_prompt)
        return if shutdown_requested? || response.nil?

        handle_summarization_response(exchange_id, response)
      rescue StandardError
        increment_failed_count
      end

      def update_status_current_exchange(exchange_id)
        @status_mutex.synchronize { @status["current_exchange_id"] = exchange_id }
      end

      def handle_empty_exchange(exchange_id)
        save_summary(exchange_id, "empty exchange", 0.0)
        @status_mutex.synchronize do
          @status["completed"] += 1
          @status["last_summary"] = "empty exchange"
        end
      end

      def build_summary_prompt(messages)
        unredacted_messages = messages.reject { |m| m["redacted"] }

        context = unredacted_messages.map do |msg|
          role = msg["role"] == "tool" ? "assistant" : msg["role"]
          content = msg["content"] || ""
          "#{role}: #{content}"
        end.join("\n\n")

        <<~PROMPT
          Summarize this exchange concisely in 1-2 sentences.
          Focus on: what the user asked, what was discussed, and key outcomes.

          Exchange:
          #{context}

          Summary:
        PROMPT
      end

      def shutdown_requested?
        @application.instance_variable_get(:@shutdown)
      end

      def handle_summarization_response(exchange_id, response)
        return increment_failed_count if response["error"]

        summary = response["content"]&.strip
        cost = response["spend"] || 0.0

        if summary && !summary.empty?
          save_summary(exchange_id, summary, cost)
          update_status_success(summary, cost)
        else
          increment_failed_count
        end
      end

      def update_status_success(summary, cost)
        @status_mutex.synchronize do
          @status["completed"] += 1
          @status["last_summary"] = summary
          @status["spend"] += cost
        end
      end

      def increment_failed_count
        @status_mutex.synchronize { @status["failed"] += 1 }
      end

      def make_llm_call_with_shutdown_check(prompt)
        # Make LLM call in a separate thread so we can check shutdown while waiting
        llm_thread = Thread.new do
          Thread.current.report_on_exception = false
          @summarizer.send_message(
            messages: [{ "role" => "user", "content" => prompt }],
            tools: nil
          )
        end

        # Poll the thread, checking for shutdown every 100ms
        response = nil
        loop do
          if llm_thread.join(0.1) # Try to join with 100ms timeout
            response = llm_thread.value
            break
          end

          # If shutdown requested while waiting, abandon this exchange
          break if @application.instance_variable_get(:@shutdown)
        end

        response
      end

      def save_summary(exchange_id, summary, cost)
        # Enter critical section for database write
        @application.send(:enter_critical_section)
        begin
          # Update exchange with summary
          @history.update_exchange_summary(
            exchange_id: exchange_id,
            summary: summary,
            model: @summarizer.model,
            cost: cost
          )
        ensure
          # Exit critical section
          @application.send(:exit_critical_section)
        end
      end
    end
  end
end
