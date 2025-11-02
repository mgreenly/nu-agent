# frozen_string_literal: true

module Nu
  module Agent
    class ChatLoopOrchestrator
      attr_reader :history, :formatter, :application, :user_actor, :event_bus

      def initialize(history:, formatter:, application:, user_actor:, event_bus:)
        @history = history
        @formatter = formatter
        @application = application
        @user_actor = user_actor
        @event_bus = event_bus
      end

      def execute(conversation_id:, client:, tool_registry:, **context)
        # Orchestrator owns the entire exchange - wrap everything in a transaction
        # Either the exchange completes successfully or nothing is saved
        session_start_time = context[:session_start_time]
        user_input = context[:user_input]

        history.transaction do
          execute_exchange(conversation_id, user_input, session_start_time, client, tool_registry)
        end
        # Transaction commits here on success, rolls back on exception
      end

      private

      def execute_exchange(conversation_id, user_input, session_start_time, client, tool_registry)
        exchange_id = create_user_message(conversation_id, user_input)
        history_messages, redacted_ranges = prepare_history_messages(conversation_id, exchange_id, session_start_time)

        request_context = { user_query: user_input, history_messages: history_messages,
                            redacted_ranges: redacted_ranges }
        messages, tools = prepare_llm_request(request_context, tool_registry, conversation_id, client)

        result = tool_calling_loop(
          messages: messages, tools: tools, client: client, history: history,
          conversation_id: conversation_id, exchange_id: exchange_id,
          tool_registry: tool_registry, application: application
        )

        if result[:error]
          handle_error_result(exchange_id,
                              result)
        else
          handle_success_result(conversation_id, exchange_id, result)
        end
      end

      def create_user_message(conversation_id, user_input)
        # Create exchange and add user message (atomic with rest of exchange)
        exchange_id = history.create_exchange(
          conversation_id: conversation_id,
          user_message: user_input
        )

        history.add_message(
          conversation_id: conversation_id,
          exchange_id: exchange_id,
          actor: user_actor,
          role: "user",
          content: user_input
        )
        formatter.display_message_created(actor: user_actor, role: "user", content: user_input)

        # Emit user input received event
        event_bus.publish(:user_input_received, { user_input: user_input, exchange_id: exchange_id })

        exchange_id
      end

      def prepare_history_messages(conversation_id, exchange_id, session_start_time)
        # Get conversation history (only unredacted messages from previous exchanges)
        all_messages = history.messages(conversation_id: conversation_id, since: session_start_time)

        # Get redacted message IDs and format as ranges
        redacted_message_ranges = nil
        if application.redact
          redacted_ids = all_messages.select { |m| m["redacted"] }.map { |m| m["id"] }.compact
          redacted_message_ranges = format_id_ranges(redacted_ids.sort) if redacted_ids.any?
        end

        # Filter to only unredacted messages from PREVIOUS exchanges (exclude current exchange)
        history_messages = all_messages.reject { |m| m["redacted"] || m["exchange_id"] == exchange_id }

        [history_messages, redacted_message_ranges]
      end

      def prepare_llm_request(request_context, tool_registry, conversation_id, client)
        # Extract request context
        user_query = request_context[:user_query]
        history_messages = request_context[:history_messages]
        redacted_ranges = request_context[:redacted_ranges]

        # Build RAG content separately for metadata
        rag_content = build_rag_content(user_query, redacted_ranges, conversation_id)

        # Get tools formatted for this client
        tools = client.format_tools(tool_registry)

        # Get system prompt from active persona
        system_prompt = if application.respond_to?(:active_persona_system_prompt)
                          application.active_persona_system_prompt
                        end

        # Use builder to construct internal format
        # Builder will merge RAG content with user_query internally
        builder = LlmRequestBuilder.new
        internal_format = builder
                          .with_system_prompt(system_prompt)
                          .with_history(history_messages)
                          .with_rag_content(rag_content)
                          .with_user_query(user_query)
                          .with_tools(tools)
                          .with_metadata(conversation_id: conversation_id)
                          .build

        # Display LLM request (verbosity based on internal format)
        formatter.display_llm_request(internal_format)

        # Extract messages and tools from internal format
        messages = internal_format[:messages]
        tools = internal_format[:tools]

        [messages, tools]
      end

      def handle_error_result(exchange_id, result)
        # Mark exchange as failed
        history.update_exchange(
          exchange_id: exchange_id,
          updates: {
            status: "failed",
            error: result[:response]["error"].to_json,
            completed_at: Time.now
          }.merge(result[:metrics])
        )
      end

      def handle_success_result(conversation_id, exchange_id, result)
        final_response = result[:response]

        # Save final assistant response (unredacted)
        save_final_response(conversation_id, exchange_id, final_response)

        # Update metrics to include final response (with nil protection)
        metrics = accumulate_final_metrics(result[:metrics], final_response)

        # Complete the exchange
        history.complete_exchange(
          exchange_id: exchange_id,
          assistant_message: final_response["content"],
          metrics: metrics
        )

        # Emit exchange completed event
        event_bus.publish(:exchange_completed, {
                            exchange_id: exchange_id,
                            conversation_id: conversation_id,
                            metrics: metrics
                          })
      end

      def save_final_response(conversation_id, exchange_id, final_response)
        history.add_message(
          conversation_id: conversation_id,
          exchange_id: exchange_id,
          actor: "orchestrator",
          role: "assistant",
          content: final_response["content"],
          model: final_response["model"],
          tokens_input: final_response["tokens"]["input"] || 0,
          tokens_output: final_response["tokens"]["output"] || 0,
          spend: final_response["spend"] || 0.0,
          redacted: false # Final response is unredacted
        )
        formatter.display_message_created(
          actor: "orchestrator",
          role: "assistant",
          content: final_response["content"],
          redacted: false
        )
      end

      def accumulate_final_metrics(metrics, final_response)
        metrics[:tokens_input] = [metrics[:tokens_input], final_response["tokens"]["input"] || 0].max
        metrics[:tokens_output] += final_response["tokens"]["output"] || 0
        metrics[:spend] += final_response["spend"] || 0.0
        metrics[:message_count] += 1
        metrics
      end

      def tool_calling_loop(messages:, client:, conversation_id:, **context)
        # Extract context parameters
        tools = context[:tools]
        history = context[:history]
        exchange_id = context[:exchange_id]
        tool_registry = context[:tool_registry]
        application = context[:application]

        # Create orchestrator and execute
        orchestrator = ToolCallOrchestrator.new(
          client: client,
          history: history,
          exchange_info: { conversation_id: conversation_id, exchange_id: exchange_id },
          tool_registry: tool_registry,
          application: application
        )

        system_prompt = if application.respond_to?(:active_persona_system_prompt)
                          application.active_persona_system_prompt
                        end
        orchestrator.execute(messages: messages, tools: tools, system_prompt: system_prompt)
      end

      def build_rag_content(_user_query, redacted_message_ranges, _conversation_id)
        # Multiple RAG sub-processes will be added here in the future
        rag_content = {}

        # RAG sub-process 1: Redacted message ranges
        rag_content[:redactions] = redacted_message_ranges if redacted_message_ranges && !redacted_message_ranges.empty?

        # RAG sub-process 2: Spell checking (if enabled)
        # TODO: Re-enable when Application class has spell_check_enabled and spellchecker methods
        # if application.spell_check_enabled && application.spellchecker
        #   spell_checker = SpellChecker.new(
        #     history: history,
        #     conversation_id: conversation_id,
        #     client: application.spellchecker
        #   )
        #   corrected_query = spell_checker.check_spelling(user_query)
        #
        #   if corrected_query != user_query
        #     rag_content[:spell_check] = { original: user_query, corrected: corrected_query }
        #   end
        # end

        rag_content
      end

      def format_id_ranges(ids)
        return "" if ids.empty?

        ranges = []
        range_start = ids.first
        range_end = ids.first

        ids.each_cons(2) do |current, nxt|
          if nxt == current + 1
            range_end = nxt
          else
            ranges << (range_start == range_end ? range_start.to_s : "#{range_start}-#{range_end}")
            range_start = nxt
            range_end = nxt
          end
        end

        # Add final range
        ranges << (range_start == range_end ? range_start.to_s : "#{range_start}-#{range_end}")

        ranges.join(", ")
      end
    end
  end
end
