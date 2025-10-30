# frozen_string_literal: true

module Nu
  module Agent
    module Workers
      # Manages background exchange summarization worker thread
      class ExchangeSummarizer < PausableTask
        def initialize(history:, summarizer:, application:, status_info:, current_conversation_id:, config_store:,
                       metrics_collector: nil)
          # Initialize PausableTask with shutdown flag from application
          super(status_info: status_info, shutdown_flag: application)

          @history = history
          @summarizer = summarizer
          @application = application
          @current_conversation_id = current_conversation_id
          @config_store = config_store
          @metrics_collector = metrics_collector
        end

        def load_verbosity
          @config_store.get_int("exchange_summarizer_verbosity", default: 0)
        end

        # Output debug message if verbosity level is sufficient
        def debug_output(message, level: 0)
          return unless @application.debug && level <= load_verbosity

          @application.output_line("[ExchangeSummarizer] #{message}", type: :debug)
        end

        # Main summarization loop - processes unsummarized exchanges
        def summarize_exchanges
          # Get exchanges that need summarization
          exchanges = @history.get_unsummarized_exchanges(exclude_conversation_id: @current_conversation_id)

          if exchanges.empty?
            debug_output("No work found (no completed exchanges need summaries)", level: 3)
            return
          end

          debug_output("Starting summarization of #{exchanges.length} exchanges", level: 0)

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

          debug_output("Finished summarization: #{@status['completed']} completed, #{@status['failed']} failed",
                       level: 0)
        end

        protected

        # Called by PausableTask in the worker loop
        def do_work
          summarize_exchanges
        end

        # Override shutdown check to use application's shutdown flag
        def shutdown_requested?
          @application.instance_variable_get(:@shutdown)
        end

        private

        def process_exchange(exchange)
          start_time = Time.now if @metrics_collector

          exchange_id = exchange["id"]
          conversation_id = exchange["conversation_id"]
          update_status_current_exchange(exchange_id)

          debug_output("Processing exchange #{exchange_id}", level: 1)

          # Get all messages for the conversation (we'll filter by exchange_id)
          messages = @history.messages(conversation_id: conversation_id, include_in_context_only: false)

          # Filter messages for this specific exchange
          exchange_messages = messages.select { |m| m["exchange_id"] == exchange_id }

          return handle_empty_exchange(exchange_id) if exchange_messages.empty?

          summary_prompt = build_summary_prompt(exchange_messages)
          return if shutdown_requested?

          debug_output("Making LLM call for exchange #{exchange_id} with #{exchange_messages.length} messages",
                       level: 2)

          response = make_llm_call_with_shutdown_check(summary_prompt)
          return if shutdown_requested? || response.nil?

          handle_summarization_response(exchange_id, response)
        rescue StandardError => e
          debug_output("Error processing exchange #{exchange_id}: #{e.message}", level: 0)
          record_failure(exchange_id, e)
          increment_failed_count
        ensure
          # Record metrics if collector is available and we started timing
          record_duration_metric(start_time) if @metrics_collector && start_time
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

        def handle_summarization_response(exchange_id, response)
          if response["error"]
            debug_output("LLM error for exchange #{exchange_id}: #{response['error']}", level: 3)
            return increment_failed_count
          end

          summary = response["content"]&.strip
          cost = response["spend"] || 0.0

          if summary && !summary.empty?
            debug_output("Got summary for exchange #{exchange_id}, cost: $#{cost.round(4)}", level: 3)
            save_summary(exchange_id, summary, cost)
            update_status_success(summary, cost)
          else
            debug_output("Empty summary response for exchange #{exchange_id}", level: 3)
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

        def record_failure(exchange_id, error)
          payload = {
            exchange_id: exchange_id,
            worker: "exchange_summarizer"
          }

          @history.create_failed_job(
            job_type: "exchange_summarization",
            ref_id: exchange_id,
            payload: payload.to_json,
            error: "#{error.class}: #{error.message}"
          )
        rescue StandardError => record_error
          # Don't let failure recording prevent the worker from continuing
          debug_output("Failed to record failure: #{record_error.message}", level: 0)
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

        def record_duration_metric(start_time)
          duration_ms = ((Time.now - start_time) * 1000).round(2)
          @metrics_collector.record_duration(:exchange_processing, duration_ms)
        end
      end
    end
  end
end
