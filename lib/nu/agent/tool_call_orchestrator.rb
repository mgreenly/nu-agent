# frozen_string_literal: true

require_relative "dependency_analyzer"
require_relative "parallel_executor"

module Nu
  module Agent
    # Manages the tool calling loop with LLM
    # rubocop:disable Metrics/ClassLength
    class ToolCallOrchestrator
      def initialize(client:, history:, exchange_info:, tool_registry:, application:)
        @client = client
        @history = history
        @formatter = application.formatter
        @console = application.console
        @conversation_id = exchange_info[:conversation_id]
        @exchange_id = exchange_info[:exchange_id]
        @tool_registry = tool_registry
        @application = application
        @dependency_analyzer = DependencyAnalyzer.new(tool_registry: tool_registry)
        @parallel_executor = ParallelExecutor.new(
          tool_registry: tool_registry,
          history: history,
          conversation_id: @conversation_id,
          client: client,
          application: application
        )
      end

      # Execute the tool calling loop
      # Returns a hash with :error, :response, and :metrics keys
      def execute(messages:, tools:, system_prompt: nil)
        metrics = {
          tokens_input: 0,
          tokens_output: 0,
          spend: 0.0,
          message_count: 0,
          tool_call_count: 0
        }

        loop do
          start_time = Time.now
          output_debug("API Request to #{@client.name}/#{@client.model}", verbosity: 2)
          response = @client.send_request(build_internal_request(messages, tools, system_prompt))
          duration = Time.now - start_time
          output_debug("API Response received after #{format_duration(duration)}", verbosity: 2)

          # Check for errors first
          if response["error"]
            handle_error_response(response, metrics)
            return { error: true, response: response, metrics: metrics }
          end

          # Update metrics
          update_metrics(metrics, response)

          # Check for tool calls
          return { error: false, response: response, metrics: metrics } unless response["tool_calls"]

          handle_tool_calls(response, messages, metrics)
          # Continue loop to get next LLM response

          # No tool calls - this is the final response
        end
      end

      private

      def build_internal_request(messages, tools, system_prompt)
        request = { messages: messages, tools: tools }
        request[:system_prompt] = system_prompt if system_prompt
        request
      end

      def handle_error_response(response, _metrics)
        # Save error message (unredacted so user can see it)
        @history.add_message(
          conversation_id: @conversation_id,
          exchange_id: @exchange_id,
          actor: "api_error",
          role: "assistant",
          content: response["content"],
          model: response["model"],
          error: response["error"],
          redacted: false
        )
        @formatter.display_message_created(
          actor: "api_error",
          role: "assistant",
          content: response["content"]
        )
      end

      def update_metrics(metrics, response)
        # tokens_input is max (largest context window used)
        # tokens_output is sum (total tokens generated)
        metrics[:tokens_input] = [metrics[:tokens_input], response["tokens"]["input"] || 0].max
        metrics[:tokens_output] += response["tokens"]["output"] || 0
        metrics[:spend] += response["spend"] || 0.0
        metrics[:message_count] += 1
      end

      def handle_tool_calls(response, messages, metrics)
        save_tool_call_message(response)
        display_tool_call_message(response)
        display_content_if_present(response["content"])

        metrics[:tool_call_count] += response["tool_calls"].length
        add_assistant_message_to_list(messages, response)

        # Analyze dependencies and batch tool calls
        batches = analyze_and_output_batches(response["tool_calls"])

        # Execute batches sequentially, but tools within each batch run in parallel
        execute_batches(batches, response["tool_calls"], messages)
      end

      # Analyze tool calls for dependencies and output batch summary
      def analyze_and_output_batches(tool_calls)
        tool_call_count = tool_calls.length
        output_debug("[DEBUG] Analyzing #{tool_call_count} tool calls for dependencies...", verbosity: 1)

        batches = @dependency_analyzer.analyze(tool_calls)
        output_batch_summary(batches, tool_call_count)
        batches
      end

      # Execute all batches sequentially
      def execute_batches(batches, all_tool_calls, messages)
        batches.each_with_index do |batch, batch_index|
          batch_number = batch_index + 1
          display_batch_tool_calls(batch, batch_number, all_tool_calls) if debug_enabled?

          # Execute batch with streaming callback for immediate output
          results = @parallel_executor.execute_batch(batch, batch_number: batch_number) do |result_data|
            # This block is called immediately when each tool thread completes
            # Save and display the result right away for streaming output
            tool_call = result_data[:tool_call]
            result = result_data[:result]
            tool_result_data = build_tool_result_data(tool_call, result)

            save_tool_result_message(tool_call, tool_result_data)
            display_result_with_context(result_data, tool_result_data)
          end

          # Still process results for messages array (but skip save/display since already done)
          results.each do |result_data|
            add_tool_result_to_messages(messages, result_data[:tool_call], result_data[:result])
          end
        end
      end

      # Display tool call requests for a batch with batch/thread context
      def display_batch_tool_calls(batch, batch_number, all_tool_calls)
        batch.each_with_index do |tool_call, index|
          thread_number = index + 1
          display_tool_call_with_context(
            tool_call,
            batch: batch_number,
            thread: thread_number,
            index: find_tool_call_index(all_tool_calls, tool_call),
            total: all_tool_calls.length
          )
        end
      end

      # Process results from a batch execution
      def process_batch_results(results, messages)
        results.each do |result_data|
          process_single_result(result_data, messages)
        end
      end

      # Process a single tool execution result
      def process_single_result(result_data, messages)
        tool_call = result_data[:tool_call]
        result = result_data[:result]
        tool_result_data = build_tool_result_data(tool_call, result)

        save_tool_result_message(tool_call, tool_result_data)
        display_result_with_context(result_data, tool_result_data)
        add_tool_result_to_messages(messages, tool_call, result)
      end

      # Display tool result with appropriate context
      def display_result_with_context(result_data, tool_result_data)
        if debug_enabled? && result_data[:batch] && result_data[:thread]
          display_tool_result_with_context(
            tool_result_data,
            batch: result_data[:batch],
            thread: result_data[:thread],
            start_time: result_data[:start_time],
            duration: result_data[:duration],
            batch_start_time: result_data[:batch_start_time]
          )
        else
          display_tool_result_message(tool_result_data)
        end
      end

      # Check if debug mode is enabled
      def debug_enabled?
        @application.respond_to?(:debug) && @application.debug
      end

      def find_tool_call_index(all_tool_calls, target_tool_call)
        all_tool_calls.index { |tc| tc["id"] == target_tool_call["id"] }&.+(1) || 0
      end

      def display_tool_call_with_context(tool_call, batch:, thread:, index:, total:)
        tool_call_formatter = @formatter.instance_variable_get(:@tool_call_formatter)
        tool_call_formatter.display(tool_call, batch: batch, thread: thread, index: index, total: total)
      end

      def display_tool_result_with_context(tool_result_data, **options)
        tool_result_formatter = @formatter.instance_variable_get(:@tool_result_formatter)
        # Build message structure expected by formatter
        message = {
          "tool_result" => tool_result_data
        }
        tool_result_formatter.display(message, **options)
      end

      def save_tool_call_message(response)
        @history.add_message(
          conversation_id: @conversation_id,
          exchange_id: @exchange_id,
          actor: "orchestrator",
          role: "assistant",
          content: response["content"],
          model: response["model"],
          tokens_input: response["tokens"]["input"] || 0,
          tokens_output: response["tokens"]["output"] || 0,
          spend: response["spend"] || 0.0,
          tool_calls: response["tool_calls"],
          redacted: true
        )
      end

      def display_tool_call_message(response)
        @formatter.display_message_created(
          actor: "orchestrator",
          role: "assistant",
          content: response["content"],
          tool_calls: response["tool_calls"],
          redacted: true
        )
      end

      def display_content_if_present(content)
        # Content is already saved to database and will be displayed by formatter.display_new_messages
        # No need to display it here - that would cause duplication
        return unless content && !content.strip.empty?

        # Just hide/show spinner to indicate content was received
        @console.hide_spinner
        @console.show_spinner("Thinking...")
      end

      def add_assistant_message_to_list(messages, response)
        messages << {
          "role" => "assistant",
          "content" => response["content"],
          "tool_calls" => response["tool_calls"]
        }
      end

      def build_tool_result_data(tool_call, result)
        {
          "name" => tool_call["name"],
          "result" => result
        }
      end

      def save_tool_result_message(tool_call, tool_result_data)
        @history.add_message(
          conversation_id: @conversation_id,
          exchange_id: @exchange_id,
          actor: "orchestrator",
          role: "tool",
          content: "",
          tool_call_id: tool_call["id"],
          tool_result: tool_result_data,
          redacted: true
        )
      end

      def display_tool_result_message(tool_result_data)
        @formatter.display_message_created(
          actor: "orchestrator",
          role: "tool",
          tool_result: tool_result_data,
          redacted: true
        )
      end

      def add_tool_result_to_messages(messages, tool_call, result)
        messages << {
          "role" => "tool",
          "tool_call_id" => tool_call["id"],
          "content" => result.is_a?(Hash) ? result.to_json : result.to_s,
          "tool_result" => {
            "name" => tool_call["name"],
            "result" => result
          }
        }
      end

      # Output debug message with verbosity check
      def output_debug(message, verbosity: 1)
        return unless @application.respond_to?(:debug) && @application.debug
        return unless @history.get_int("tools_verbosity", default: 0) >= verbosity

        @application.output_line(message, type: :debug)
      end

      # Output batch planning summary
      def output_batch_summary(batches, tool_call_count)
        return unless debug_enabled? && @history.get_int("tools_verbosity", default: 0) >= 1

        output_batch_count_summary(batches.length, tool_call_count)
        output_detailed_batch_info(batches) if @history.get_int("tools_verbosity", default: 0) >= 2
      end

      # Output high-level batch count summary
      def output_batch_count_summary(batch_count, tool_call_count)
        batches_text = batch_count == 1 ? "batch" : "batches"
        calls_text = tool_call_count == 1 ? "tool call" : "tool calls"
        @application.output_line(
          "[DEBUG] Created #{batch_count} #{batches_text} from #{tool_call_count} #{calls_text}",
          type: :debug
        )
      end

      # Output detailed information about each batch
      def output_detailed_batch_info(batches)
        batches.each_with_index do |batch, index|
          batch_number = index + 1
          output_single_batch_info(batch, batch_number)
        end
      end

      # Output information about a single batch
      def output_single_batch_info(batch, batch_number)
        tool_counts = count_tools_in_batch(batch)
        tool_summary = tool_counts.map { |name, count| "#{name} x#{count}" }.join(", ")
        batch_type = determine_batch_type(batch)
        tools_text = batch.length == 1 ? "tool" : "tools"

        @application.output_line(
          "[DEBUG] Batch #{batch_number}: #{batch.length} #{tools_text} (#{tool_summary}) - #{batch_type}",
          type: :debug
        )
      end

      # Determine the type of batch (barrier or parallel)
      def determine_batch_type(batch)
        if batch.length == 1 && barrier_tool?(batch.first)
          "BARRIER (runs alone)"
        else
          "parallel execution"
        end
      end

      # Count occurrences of each tool in a batch
      def count_tools_in_batch(batch)
        counts = Hash.new(0)
        batch.each do |tool_call|
          counts[tool_call["name"]] += 1
        end
        counts
      end

      # Check if a tool is a barrier tool (unconfined write)
      def barrier_tool?(tool_call)
        metadata = @tool_registry.metadata_for(tool_call["name"])
        return false unless metadata

        metadata[:operation_type] == :write && metadata[:scope] == :unconfined
      end

      # Format duration for display
      def format_duration(duration)
        if duration < 1.0
          "#{(duration * 1000).round}ms"
        else
          "#{format('%.2f', duration)}s"
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
