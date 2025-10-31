# frozen_string_literal: true

module Nu
  module Agent
    # ParallelExecutor handles concurrent execution of tool call batches using Ruby threads.
    #
    # This class is responsible for executing batches of independent tool calls in parallel,
    # maximizing throughput while maintaining result ordering and thread safety. It uses
    # Ruby's Thread class to create a separate thread for each tool call within a batch.
    #
    # Key Features:
    # - Parallel execution: All tools in a batch run concurrently in separate threads
    # - Order preservation: Results are returned in the same order as input tool calls
    # - Error isolation: Exceptions in one tool don't affect execution of other tools
    # - Thread safety: Each tool executes in an isolated context with proper error handling
    #
    # Thread Model:
    # For each batch, the executor creates one thread per tool call. All threads are spawned
    # immediately and run concurrently. The executor waits for all threads to complete before
    # returning results. This maximizes parallelism within a batch while keeping the
    # implementation simple (no thread pooling needed for short-lived tool calls).
    #
    # Error Handling:
    # If a tool execution raises an exception, the exception is caught and returned as an
    # error result. This ensures that one failing tool doesn't prevent other tools from
    # completing their execution. The error result includes the exception message, class,
    # and backtrace for debugging.
    #
    # Result Ordering:
    # Results are guaranteed to be returned in the same order as the input tool_calls array,
    # regardless of which tools complete first. This is achieved by tracking the original
    # index of each tool call and sorting results by index before returning.
    #
    # Examples:
    #   executor = ParallelExecutor.new(
    #     tool_registry: registry,
    #     history: history,
    #     conversation_id: 123
    #   )
    #
    #   # Execute 3 file reads in parallel
    #   tool_calls = [
    #     { "name" => "file_read", "arguments" => { "file" => "a.txt" } },
    #     { "name" => "file_read", "arguments" => { "file" => "b.txt" } },
    #     { "name" => "file_read", "arguments" => { "file" => "c.txt" } }
    #   ]
    #   results = executor.execute_batch(tool_calls)
    #   # => [
    #   #   { tool_call: {...}, result: "contents of a.txt" },
    #   #   { tool_call: {...}, result: "contents of b.txt" },
    #   #   { tool_call: {...}, result: "contents of c.txt" }
    #   # ]
    class ParallelExecutor
      def initialize(tool_registry:, history:, conversation_id: nil, client: nil, application: nil)
        @tool_registry = tool_registry
        @history = history
        @conversation_id = conversation_id
        @client = client
        @application = application
      end

      # Execute a batch of tool calls in parallel and return results
      #
      # This method spawns a separate thread for each tool call, executes them concurrently,
      # waits for all to complete, and returns results in the original order.
      #
      # Algorithm:
      # 1. Create a thread for each tool call, tracking its original index
      # 2. Each thread executes the tool with error handling
      # 3. Wait for all threads to complete using Thread#value
      # 4. Sort results by original index to maintain input order
      # 5. Return results without the index tracking
      #
      # @param tool_calls [Array<Hash>] Array of tool call hashes with "name" and "arguments" keys
      # @param batch_number [Integer, nil] Optional batch number for visibility/debugging
      # @return [Array<Hash>] Array of results with format: { tool_call: ..., result: ..., batch: ..., thread: ... }
      #   Results are in the same order as input tool_calls, regardless of completion order
      #   If batch_number provided, includes :batch and :thread keys for observability
      def execute_batch(tool_calls, batch_number: nil)
        # Output batch execution start message
        output_batch_start(tool_calls, batch_number) if batch_number

        start_time = Time.now

        # Create threads for parallel execution
        # Each thread tracks its original index to enable result ordering
        # If batch_number provided, also track thread number for visibility
        threads = []
        tool_calls.each_with_index do |tool_call, index|
          thread_number = index + 1 # Thread numbers start at 1 for display
          thread = Thread.new do
            # Track tool execution timing
            tool_start_time = Time.now
            result = execute_tool_with_error_handling(tool_call)
            tool_end_time = Time.now
            duration = tool_end_time - tool_start_time

            result_data = { index: index, tool_call: tool_call, result: result }
            # Add batch/thread info if batch_number provided
            if batch_number
              result_data[:batch] = batch_number
              result_data[:thread] = thread_number
            end
            # Add timing info (always include for observability)
            result_data[:start_time] = tool_start_time
            result_data[:end_time] = tool_end_time
            result_data[:duration] = duration
            result_data
          end
          threads << thread
        end

        # Wait for all threads to complete and collect their return values
        # Thread#value blocks until the thread completes and returns its final value
        results_with_index = threads.map(&:value)

        # Output batch execution complete message with timing
        elapsed = Time.now - start_time
        output_batch_complete(tool_calls, batch_number, elapsed) if batch_number

        # Sort by original index to maintain order, then strip the index field
        # This ensures results match the order of input tool_calls
        results_with_index.sort_by { |r| r[:index] }.map do |r|
          result = { tool_call: r[:tool_call], result: r[:result] }
          # Preserve batch/thread info if present
          result[:batch] = r[:batch] if r[:batch]
          result[:thread] = r[:thread] if r[:thread]
          # Preserve timing info (always include for observability)
          result[:start_time] = r[:start_time]
          result[:end_time] = r[:end_time]
          result[:duration] = r[:duration]
          result
        end
      end

      private

      # Execute a tool with exception handling
      #
      # Wraps tool execution in a rescue block to isolate failures. If the tool raises
      # an exception, it's caught and returned as an error hash instead of propagating.
      # This prevents one failing tool from crashing other concurrent tools.
      #
      # @param tool_call [Hash] Tool call hash with "name" and "arguments"
      # @return [Object, Hash] Tool result on success, or error hash on exception
      def execute_tool_with_error_handling(tool_call)
        execute_tool(tool_call)
      rescue StandardError => e
        # Capture exceptions and return them as error results
        # This prevents one failing tool from crashing other parallel tools
        {
          error: "Exception during tool execution: #{e.message}",
          exception: e,
          exception_class: e.class.name,
          backtrace: e.backtrace&.first(5)
        }
      end

      # Execute a single tool call via the tool registry
      #
      # Delegates to the tool registry's execute method with the tool name, arguments,
      # history, and execution context. Each tool execution gets an isolated context.
      #
      # @param tool_call [Hash] Tool call hash with "name" and "arguments"
      # @return [Object] Tool execution result
      def execute_tool(tool_call)
        @tool_registry.execute(
          name: tool_call["name"],
          arguments: tool_call["arguments"],
          history: @history,
          context: build_context
        )
      end

      # Build execution context for tool calls
      #
      # Constructs a context hash with metadata about the current execution environment.
      # This context is passed to each tool and can be used for logging, metrics, etc.
      #
      # @return [Hash] Context hash with conversation_id, model, and application keys
      def build_context
        context = {}
        context["conversation_id"] = @conversation_id if @conversation_id
        context["model"] = @client.model if @client
        context["application"] = @application if @application
        context
      end

      # Output batch execution start message
      #
      # Outputs a debug message indicating that a batch is starting execution.
      # Only outputs if application has debug mode and verbosity level 2 or higher.
      #
      # @param tool_calls [Array<Hash>] Array of tool calls in the batch
      # @param batch_number [Integer] Batch number for display
      def output_batch_start(tool_calls, batch_number)
        return unless @application.respond_to?(:debug) && @application.debug
        return unless @application.respond_to?(:verbosity) && @application.verbosity >= 2

        tool_count = tool_calls.length
        thread_text = tool_count == 1 ? "thread" : "parallel threads"
        @application.output_line(
          "[DEBUG] Executing batch #{batch_number}: #{tool_count} tool#{unless tool_count == 1
                                                                          's'
                                                                        end} in #{thread_text}", type: :debug
        )
      end

      # Output batch execution complete message with timing
      #
      # Outputs a debug message indicating that a batch has completed execution,
      # including the elapsed time. Only outputs if application has debug mode
      # and verbosity level 2 or higher.
      #
      # @param tool_calls [Array<Hash>] Array of tool calls that were executed
      # @param batch_number [Integer] Batch number for display
      # @param elapsed [Float] Elapsed time in seconds
      def output_batch_complete(tool_calls, batch_number, elapsed)
        return unless @application.respond_to?(:debug) && @application.debug
        return unless @application.respond_to?(:verbosity) && @application.verbosity >= 2

        tool_count = tool_calls.length
        elapsed_str = format_elapsed_time(elapsed)
        @application.output_line(
          "[DEBUG] Batch #{batch_number} complete: #{tool_count}/#{tool_count} tools in #{elapsed_str}", type: :debug
        )
      end

      # Format elapsed time for display
      #
      # Formats elapsed time in either milliseconds or seconds depending on magnitude.
      # - Less than 1 second: shows in milliseconds (e.g., "350ms")
      # - 1 second or more: shows in seconds with 2 decimal places (e.g., "1.23s")
      #
      # @param elapsed [Float] Elapsed time in seconds
      # @return [String] Formatted elapsed time string
      def format_elapsed_time(elapsed)
        if elapsed < 1.0
          "#{(elapsed * 1000).round}ms"
        else
          "#{format('%.2f', elapsed)}s"
        end
      end
    end
  end
end
