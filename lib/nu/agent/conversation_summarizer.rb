# frozen_string_literal: true

module Nu
  module Agent
    # Manages background conversation summarization worker thread
    class ConversationSummarizer
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
          summarize_conversations
        rescue StandardError
          @status_mutex.synchronize do
            @status["running"] = false
          end
        end
      end

      # Main summarization loop - processes unsummarized conversations
      def summarize_conversations
        # Get conversations that need summarization
        conversations = @history.get_unsummarized_conversations(exclude_id: @current_conversation_id)

        return if conversations.empty?

        # Update status
        @status_mutex.synchronize do
          @status["running"] = true
          @status["total"] = conversations.length
          @status["completed"] = 0
          @status["failed"] = 0
        end

        conversations.each do |conv|
          # Check for shutdown signal before processing each conversation
          break if @application.instance_variable_get(:@shutdown)

          process_conversation(conv)
        end

        # Mark as complete
        @status_mutex.synchronize do
          @status["running"] = false
          @status["current_conversation_id"] = nil
        end
      end

      private

      def process_conversation(conv)
        conv_id = conv["id"]
        update_status_current_conversation(conv_id)

        messages = @history.messages(conversation_id: conv_id, include_in_context_only: false)
        return handle_empty_conversation(conv_id) if messages.empty?

        summary_prompt = build_summary_prompt(messages)
        return if shutdown_requested?

        response = make_llm_call_with_shutdown_check(summary_prompt)
        return if shutdown_requested? || response.nil?

        handle_summarization_response(conv_id, response)
      rescue StandardError
        increment_failed_count
      end

      def update_status_current_conversation(conv_id)
        @status_mutex.synchronize { @status["current_conversation_id"] = conv_id }
      end

      def handle_empty_conversation(conv_id)
        save_summary(conv_id, "empty conversation", 0.0)
        @status_mutex.synchronize do
          @status["completed"] += 1
          @status["last_summary"] = "empty conversation"
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
          Summarize this conversation concisely in 2-3 sentences.
          Focus on: what the user wanted, key decisions made, and outcomes.

          Conversation:
          #{context}

          Summary:
        PROMPT
      end

      def shutdown_requested?
        @application.instance_variable_get(:@shutdown)
      end

      def handle_summarization_response(conv_id, response)
        return increment_failed_count if response["error"]

        summary = response["content"]&.strip
        cost = response["spend"] || 0.0

        if summary && !summary.empty?
          save_summary(conv_id, summary, cost)
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

          # If shutdown requested while waiting, abandon this conversation
          break if @application.instance_variable_get(:@shutdown)
        end

        response
      end

      def save_summary(conversation_id, summary, cost)
        # Enter critical section for database write
        @application.send(:enter_critical_section)
        begin
          # Update conversation with summary
          @history.update_conversation_summary(
            conversation_id: conversation_id,
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
