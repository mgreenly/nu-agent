# Plan for Parallel Tool Execution in Agentic Coding Assistant

## Overview
This document outlines a proposed approach to enhance the performance of the agentic coding assistant by implementing parallel execution of tool calls. The primary goal is to reduce the total execution time when multiple tools are invoked in a single response, thereby making the assistant faster for coding tasks.

## Current Implementation
Currently, tool calls are executed sequentially in the `handle_tool_calls` method within `tool_call_orchestrator.rb`. The method iterates over each tool call in a loop, waiting for one to complete before starting the next. This sequential processing is a bottleneck, especially when tool calls are independent and could run concurrently.

### Key Architectural Components
- **Tool Registry**: Tools are managed in `tool_registry.rb`, where each tool's execution is handled independently via the `execute` method (lines 30-35), but orchestration of multiple calls happens elsewhere.
- **Background Workers**: Managed by `background_worker_manager.rb`, long-running tasks like summarization and embeddings run in separate threads, independent of user-triggered tool calls. Workers use mutexes for synchronization (lines 33, 68, 91).
- **Console I/O**: `console_io.rb` handles user input/output with thread-safe mechanisms (mutex and queue, lines 51-56, 229-247), ensuring background threads can output results without interfering with user input.
- **Main Application**: `application.rb` coordinates the REPL loop (lines 209-229), uses `ConsoleIO` for I/O, and manages background workers (lines 149-159), with mutexes for critical sections (lines 190-206).

## Proposed Approach
To address this bottleneck, we propose modifying the `handle_tool_calls` method to execute independent tool calls in parallel using Ruby's threading capabilities. The high-level steps are:

1. **Dependency Analysis**: Identify independent tool calls that can run concurrently based on operation type (read/write), scope (confined/unconfined), and affected resources (e.g., file paths).
2. **Concurrent Execution**: Use Ruby's `Thread` class to execute independent tool calls in parallel within defined batches.
3. **Synchronization and Ordering**: Collect results from all tool calls and process them in the original order to maintain consistency in the message history.

### Dependency Management Rules
1. **Tool Classification**: Extend `tool_registry.rb` to include metadata for each tool: `operation_type` (:read or :write) and `scope` (:confined or :unconfined). For example, `file_read` is `:read, :confined`, while `execute_bash` is `:write, :unconfined`.
2. **Path Extraction**: For confined tools, extract affected paths from arguments (e.g., `file` parameter in `file_read`).
3. **Execution Rules**:
   - **Read Tools**: Can run in parallel with other reads unless blocked by a prior write on the same path.
   - **Write Tools with Specific Paths**: Must wait for prior operations on the same path and block subsequent operations on that path until complete.
   - **Write Tools with Unconfined Scope (e.g., `execute_bash`)**: Must wait for all prior tool calls to complete (acting as a barrier) and block all subsequent tool calls until finished, running in isolation.

### Architectural Patterns
1. **Metadata Pattern**: Add `operation_type` and `scope` to tool definitions in `tool_registry.rb` for classification without altering tool logic.
2. **Dependency Injection**: Pass tool registry metadata to `ToolCallOrchestrator` for decision-making, promoting loose coupling.
3. **Pipeline Processing**: Structure `handle_tool_calls` as a pipeline: analyze dependencies, batch calls, execute batches (parallel within batches), and aggregate results.
4. **Barrier Synchronization**: Treat unconfined write tools as barriers in the execution pipeline for safety.

### Integration with Current Architecture
- **Threading Model**: Use `Thread` for each tool call within a batch in `tool_call_orchestrator.rb`, similar to how `BackgroundWorkerManager` starts worker threads (lines 46-47). No thread pool needed initially as tool calls are typically short-lived.
- **Output Handling**: Use `ConsoleIO#puts` from tool threads to queue output results. The existing `Queue` and `Mutex` in `ConsoleIO` (lines 51-56) ensure thread-safe display without interleaving.
- **REPL Responsiveness**: Ensure the REPL loop in `application.rb` (lines 209-229) remains responsive by leveraging `ConsoleIO`’s asynchronous output handling via `IO.select` (lines 158-172).
- **Separation from Workers**: Background workers (`background_worker_manager.rb`) are distinct from tool calls. Parallel tool execution is independent, with potential conflicts mitigated by dependency rules.

## Conceptual Code Change
Below is a conceptual modification to the `handle_tool_calls` method in `tool_call_orchestrator.rb` (around lines 82-94):

```ruby
require 'thread'

# Define tools with unconfined scope (could be in tool_registry.rb as metadata)
UNCONFINED_WRITE_TOOLS = ['execute_bash', 'execute_python'].freeze

# Analyze tool calls for dependencies
tool_call_batches = []
current_batch = []
path_writes = {}  # Track last write operation per path

response["tool_calls"].each do |tool_call|
  tool_name = tool_call.dig("function", "name")
  tool_info = $tool_registry.get_tool(tool_name)
  operation_type = tool_info[:operation_type] || infer_operation_type(tool_name)  # e.g., :read or :write
  affected_path = extract_path_from_arguments(tool_call.dig("function", "arguments"))  # e.g., file parameter
  is_unconfined = UNCONFINED_WRITE_TOOLS.include?(tool_name) && operation_type == :write

  if is_unconfined
    # Unconfined write tools act as a barrier: wait for all prior operations and block subsequent ones
    tool_call_batches << current_batch unless current_batch.empty?
    tool_call_batches << [tool_call]  # Solo batch for this tool
    current_batch = []
    path_writes.each_key { |path| path_writes[path] = tool_call }  # Mark as blocking all paths
  elsif operation_type == :write && affected_path
    # Wait for any prior operations on this path
    if path_writes[affected_path] || current_batch.any? { |tc| extract_path_from_arguments(tc.dig("function", "arguments")) == affected_path }
      tool_call_batches << current_batch unless current_batch.empty?
      current_batch = [tool_call]
    else
      current_batch << tool_call
    end
    path_writes[affected_path] = tool_call
  elsif operation_type == :read && affected_path && path_writes[affected_path]
    # If there's a prior write on this path, start a new batch
    tool_call_batches << current_batch unless current_batch.empty?
    current_batch = [tool_call]
  else
    # Safe to add to current batch (independent read or no conflict)
    current_batch << tool_call
  end
end
tool_call_batches << current_batch unless current_batch.empty?

# Execute batches sequentially, but parallelize within each batch
tool_call_results = []
tool_call_batches.each do |batch|
  threads = []
  batch_results = []
  batch.each do |tool_call|
    threads << Thread.new do
      result = execute_tool_call(tool_call, messages.dup)
      batch_results << { tool_call: tool_call, result: result }
    end
  end
  threads.each(&:join)
  tool_call_results.concat(batch_results)
end

# Process results in original order
tool_call_results.sort_by { |r| response["tool_calls"].index(r[:tool_call]) }.each do |result_data|
  tool_call = result_data[:tool_call]
  result = result_data[:result]
  tool_result_data = build_tool_result_data(tool_call, result)
  save_tool_result_message(tool_call, tool_result_data)
  display_tool_result_message(tool_result_data)
  add_tool_result_to_messages(messages, tool_call, result)
end
```

## Explanation of Changes
- **Dependency Batching**: Tool calls are grouped into batches based on operation type, scope, and path to prevent conflicts.
- **Thread Creation**: Each tool call in a batch is executed in a separate thread, allowing parallel processing within batches.
- **Result Collection**: Results are stored with their corresponding tool call for later processing.
- **Synchronization**: `threads.each(&:join)` ensures all threads in a batch complete before moving to the next batch.
- **Ordered Processing**: Results are sorted by the original order of tool calls to ensure the message history reflects the intended sequence.

## Challenges and Considerations
1. **Race Conditions**: If multiple tools access the same resource (e.g., a file), parallel execution could lead to conflicts. The dependency batching mitigates this, but edge cases (e.g., dynamic paths) need testing.
2. **Thread Safety**: Ensure that `execute_tool_call` and shared state (like `@history`) are thread-safe, using mutexes if needed, following the pattern in `Application` (lines 190-206).
3. **Performance Overhead**: For very quick tool calls, thread creation overhead might outweigh benefits. A thread pool or conditional parallelism could be explored.
4. **Output Volume**: If many parallel tools produce output, `ConsoleIO` queue backlog is unlikely to block REPL due to `IO.select`, but monitor during testing.
5. **Resource Conflicts with Workers**: Rare conflicts between tool threads and background workers can be mitigated by mutexes for shared resources.
6. **Interrupt Handling**: Ensure `ConsoleIO`’s interrupt handling (Ctrl-C, lines 261-262) works during parallel tool execution, with threads checking for interrupts or being killable.

## Next Steps
- **Refine Dependency Analysis**: Develop a robust mechanism to detect potential conflicts based on tool arguments (e.g., file paths). Test batching logic for correctness.
- **Test Thread Safety**: Audit `execute_tool_call` and related methods to identify and resolve thread-safety issues with shared resources.
- **Performance Benchmarking**: Implement a prototype of this approach and benchmark it against the current sequential execution to quantify performance gains.
- **Iterative Improvements**: Based on testing, consider advanced concurrency models (e.g., thread pools via `concurrent-ruby`) or integration of complex tool calls with `BackgroundWorkerManager` if resource-intensive.
- **Draft Code Changes**: Prepare specific updates for `tool_call_orchestrator.rb` to implement threading, batching, and output via `ConsoleIO`.

## Additional Enhancements
Beyond parallel execution, other optimizations could be explored:
1. **Batch Processing**: Modify tools to accept batch inputs where applicable (e.g., `file_read` could read multiple files in one call). This would require updates to tool definitions and the registry.
2. **Tool-Specific Caching**: Add caching logic at the registry level or within individual tools to store results of frequent operations.

## Feedback and Refinement
This plan is a comprehensive blueprint for parallel tool execution. Feedback is welcome on:
- Dependency analysis and batching logic for edge cases (e.g., dynamic paths, non-file resources).
- Thread safety mechanisms for shared state and integration with background workers.
- Prioritization of this optimization versus other enhancements like batch processing or caching.

**Last Updated**: October 30, 2025
