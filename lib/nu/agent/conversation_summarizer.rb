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

        # Update current conversation being processed
        @status_mutex.synchronize do
          @status["current_conversation_id"] = conv_id
        end

        # Get all messages for this conversation
        messages = @history.messages(conversation_id: conv_id, include_in_context_only: false)

        # Handle empty conversations
        if messages.empty?
          save_summary(conv_id, "empty conversation", 0.0)
          @status_mutex.synchronize do
            @status["completed"] += 1
            @status["last_summary"] = "empty conversation"
          end
          return
        end

        # Filter to only unredacted messages (same as we do for context)
        unredacted_messages = messages.reject { |m| m["redacted"] }

        # Build prompt for summarization
        context = unredacted_messages.map do |msg|
          role = msg["role"] == "tool" ? "assistant" : msg["role"]
          content = msg["content"] || ""
          "#{role}: #{content}"
        end.join("\n\n")

        summary_prompt = <<~PROMPT
          Summarize this conversation concisely in 2-3 sentences.
          Focus on: what the user wanted, key decisions made, and outcomes.

          Conversation:
          #{context}

          Summary:
        PROMPT

        # Check for shutdown before making expensive LLM call
        return if @application.instance_variable_get(:@shutdown)

        # Make LLM call with shutdown awareness
        response = make_llm_call_with_shutdown_check(summary_prompt)

        # Skip saving if shutdown was requested or response is nil
        return if @application.instance_variable_get(:@shutdown)
        return if response.nil?

        # Handle response
        if response["error"]
          @status_mutex.synchronize do
            @status["failed"] += 1
          end
          return
        end

        summary = response["content"]&.strip
        cost = response["spend"] || 0.0

        if summary && !summary.empty?
          save_summary(conv_id, summary, cost)

          # Update status and accumulate spend
          @status_mutex.synchronize do
            @status["completed"] += 1
            @status["last_summary"] = summary
            @status["spend"] += cost
          end
        else
          @status_mutex.synchronize do
            @status["failed"] += 1
          end
        end
      rescue StandardError
        @status_mutex.synchronize do
          @status["failed"] += 1
        end
      end

      def make_llm_call_with_shutdown_check(prompt)
        # Make LLM call in a separate thread so we can check shutdown while waiting
        llm_thread = Thread.new do
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
