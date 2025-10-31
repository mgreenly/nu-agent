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

## Implementation Plan

### Development Methodology
- **TDD Required**: All work follows strict Red-Green-Refactor cycle. Write failing tests first, implement minimal code to pass, then refactor.
- **Git Workflow**: Commit frequently after each green test or logical unit. DO NOT push to GitHub until explicitly requested.
- **Quality Gates**: 100% test coverage, zero lint violations, all specs passing at every commit. NO EXCEPTIONS.
- **Test Execution**: Run full test suite (`bundle exec rspec`) and lint (`bundle exec rubocop`) before every commit.

### Phase 1: Tool Metadata Foundation (TDD)

**Objective**: Extend ToolRegistry and tool definitions to include operation_type and scope metadata.

**TDD Steps**:
1. **RED**: Write spec for ToolRegistry metadata storage
   - Test: `tool_registry_spec.rb` - verify tools can be registered with metadata
   - Test: `tool_registry_spec.rb` - verify metadata retrieval for registered tools
   - Test: `tool_registry_spec.rb` - verify default values when metadata not provided
   - Commit: "Add failing specs for tool metadata in ToolRegistry"

2. **GREEN**: Implement metadata in ToolRegistry
   - Update `ToolRegistry#register` to accept and store metadata
   - Update `ToolRegistry#find` to return metadata with tool
   - Add `ToolRegistry#metadata_for(name)` method
   - Run tests until green
   - Commit: "Implement tool metadata storage in ToolRegistry"

3. **RED**: Write specs for tool metadata declarations
   - Test: Pick 3 sample tools (FileRead, FileWrite, ExecuteBash)
   - Test: Verify each tool declares operation_type and scope
   - Commit: "Add failing specs for tool metadata declarations"

4. **GREEN**: Add metadata to tool base interface
   - Add `operation_type` and `scope` methods to tool classes
   - Implement for FileRead (:read, :confined)
   - Implement for FileWrite (:write, :confined)
   - Implement for ExecuteBash (:write, :unconfined)
   - Run tests until green
   - Commit: "Add metadata methods to sample tools"

5. **REFACTOR**: Add metadata to all remaining tools
   - Update all 21 tools with appropriate metadata
   - Verify all specs pass
   - Run full test suite + coverage check
   - Commit: "Add metadata to all tools"

**Acceptance Criteria**:
- [x] All tools have operation_type (:read or :write)
- [x] All tools have scope (:confined or :unconfined)
- [x] ToolRegistry stores and retrieves metadata correctly
- [x] 100% test coverage for new metadata functionality
- [x] Zero rubocop violations
- [x] All existing tests still pass

**Status**: ✅ COMPLETE (6 commits)
**Commits**: d5096c2, cce1837, 3986e66, 8596270, 82860b3

**Estimated Commits**: 5-6

---

### Phase 2: Resource Path Extraction (TDD)

**Objective**: Build logic to extract affected file paths and resources from tool arguments for dependency tracking.

**TDD Steps**:
1. **RED**: Write spec for PathExtractor class
   - Test: Extract file path from FileRead arguments
   - Test: Extract file path from FileWrite arguments
   - Test: Extract multiple paths from FileCopy arguments
   - Test: Return nil for ExecuteBash (unconfined)
   - Test: Return nil for DatabaseQuery (different resource type)
   - Test: Handle missing/nil arguments gracefully
   - Commit: "Add failing specs for PathExtractor"

2. **GREEN**: Implement PathExtractor class
   - Create `lib/nu/agent/path_extractor.rb`
   - Implement `extract(tool_name, arguments)` method
   - Use tool metadata to determine extraction strategy
   - Handle file, source_file, destination_file, path parameters
   - Run tests until green
   - Commit: "Implement PathExtractor for dependency analysis"

3. **RED**: Write specs for path normalization
   - Test: Resolve relative paths to absolute paths
   - Test: Normalize paths (handle .., ., //)
   - Test: Handle nil/empty paths
   - Commit: "Add failing specs for path normalization"

4. **GREEN**: Implement path normalization
   - Add `normalize_path(path)` method to PathExtractor
   - Use `File.expand_path` for normalization
   - Run tests until green
   - Commit: "Implement path normalization in PathExtractor"

5. **REFACTOR**: Edge case handling
   - Add specs for symlinks, non-existent paths
   - Update implementation as needed
   - Run full test suite + coverage
   - Commit: "Add edge case handling for path extraction"

**Acceptance Criteria**:
- [x] PathExtractor correctly identifies file paths from all file-based tools
- [x] PathExtractor returns nil for unconfined tools
- [x] Paths are normalized to absolute form
- [x] 100% test coverage for PathExtractor
- [x] Zero rubocop violations
- [x] All existing tests still pass

**Status**: ✅ COMPLETE (5 commits)
**Commits**: 576215e, ddbd7cb, 2366bff, 7f1feda, ef03139

**Estimated Commits**: 5-6

---

### Phase 3: Dependency Analysis & Batching (TDD)

**Objective**: Implement the core logic that analyzes tool call dependencies and groups them into parallelizable batches.

**TDD Steps**:
1. **RED**: Write specs for DependencyAnalyzer - basic batching
   - Test: Single tool call produces single batch
   - Test: Two independent read tools batch together
   - Test: Two read tools on same path batch together
   - Test: Read then write on same path creates two batches
   - Commit: "Add failing specs for basic dependency batching"

2. **GREEN**: Implement DependencyAnalyzer skeleton
   - Create `lib/nu/agent/dependency_analyzer.rb`
   - Implement `analyze(tool_calls)` method returning batches
   - Basic logic for read/read compatibility
   - Run tests until green
   - Commit: "Implement basic dependency batching"

3. **RED**: Write specs for write dependency rules
   - Test: Write then write on same path creates two batches
   - Test: Write then read on same path creates two batches
   - Test: Write on path A, read on path B batches together
   - Test: Multiple writes on different paths batch together
   - Commit: "Add failing specs for write dependency rules"

4. **GREEN**: Implement write dependency logic
   - Add path tracking during analysis
   - Implement write/write conflict detection
   - Implement write blocks subsequent read logic
   - Run tests until green
   - Commit: "Implement write dependency analysis"

5. **RED**: Write specs for unconfined tool barriers
   - Test: ExecuteBash forces solo batch
   - Test: Tools before ExecuteBash in separate batch
   - Test: Tools after ExecuteBash in separate batch
   - Test: Multiple ExecuteBash calls each get solo batch
   - Commit: "Add failing specs for unconfined tool barriers"

6. **GREEN**: Implement barrier logic for unconfined tools
   - Detect unconfined write tools (operation_type: :write, scope: :unconfined)
   - Force batch boundary before and after
   - Run tests until green
   - Commit: "Implement barrier synchronization for unconfined tools"

7. **REFACTOR**: Complex scenarios
   - Add specs for 10+ tool calls with mixed dependencies
   - Add specs for database tools (different resource type)
   - Add specs for tools with no extractable paths
   - Update implementation to handle all scenarios
   - Run full test suite + coverage
   - Commit: "Add comprehensive dependency analysis scenarios"

**Acceptance Criteria**:
- [x] DependencyAnalyzer correctly batches independent tools together
- [x] Read/write dependencies on same path are respected
- [x] Unconfined tools act as barriers (solo batches)
- [x] Complex multi-tool scenarios produce correct batches
- [x] 100% test coverage for DependencyAnalyzer
- [x] Zero rubocop violations
- [x] All existing tests still pass

**Status**: ✅ COMPLETE (7 commits)
**Commits**: 45996e1, 28439e3, 103482b, 7d6bf94, c4f845e, d2c0b78

**Estimated Commits**: 7-8

---

### Phase 4: Parallel Execution Engine (TDD)

**Objective**: Implement thread-based parallel execution within batches with result collection and ordering.

**TDD Steps**:
1. **RED**: Write specs for ParallelExecutor - single tool
   - Test: Execute single tool call, return result
   - Test: Preserve tool_call and result in output
   - Test: Handle tool execution errors gracefully
   - Commit: "Add failing specs for single tool execution"

2. **GREEN**: Implement ParallelExecutor skeleton
   - Create `lib/nu/agent/parallel_executor.rb`
   - Implement `execute_batch(tool_calls)` method
   - Execute single tool sequentially for now
   - Run tests until green
   - Commit: "Implement basic single tool execution"

3. **RED**: Write specs for parallel execution
   - Test: Execute 3 independent tools in parallel
   - Test: All tools complete before returning
   - Test: Results returned in original order
   - Test: Verify parallel execution (timing-based or mock threads)
   - Commit: "Add failing specs for parallel execution"

4. **GREEN**: Implement parallel execution with threads
   - Use `Thread.new` for each tool in batch
   - Collect results with tool_call reference
   - Use `threads.each(&:join)` to wait for completion
   - Sort results by original order before returning
   - Run tests until green
   - Commit: "Implement parallel thread-based execution"

5. **RED**: Write specs for thread safety
   - Test: Shared state access (mock History, ToolRegistry)
   - Test: Concurrent tool executions don't interfere
   - Test: Thread exceptions don't crash other threads
   - Commit: "Add failing specs for thread safety"

6. **GREEN**: Implement thread safety measures
   - Ensure each thread gets isolated execution context
   - Wrap thread bodies in exception handlers
   - Store exceptions in results for later handling
   - Run tests until green
   - Commit: "Implement thread safety and exception handling"

7. **RED**: Write specs for result ordering guarantee
   - Test: 5 tools with random execution times
   - Test: Results always match original tool_call order
   - Test: Verify index-based ordering logic
   - Commit: "Add failing specs for result ordering"

8. **GREEN**: Implement robust result ordering
   - Store original index with each tool_call
   - Sort results by index before returning
   - Run tests until green
   - Commit: "Implement guaranteed result ordering"

9. **REFACTOR**: Performance and edge cases
   - Add specs for empty batches
   - Add specs for tools with slow execution
   - Add specs for tools that modify shared resources
   - Update implementation as needed
   - Run full test suite + coverage
   - Commit: "Add edge cases and performance specs"

**Acceptance Criteria**:
- [x] ParallelExecutor executes batches using threads
- [x] Results are returned in original order
- [x] Thread exceptions are captured and handled
- [x] Thread-safe execution with isolated contexts
- [x] 100% test coverage for ParallelExecutor
- [x] Zero rubocop violations
- [x] All existing tests still pass

**Status**: ✅ COMPLETE (6 commits)
**Commits**: ca76f4f, 71ad455, c1c85ee, d84b3e5, 5dbe0ab, a318d70, 4dc1c32

**Estimated Commits**: 9-10

---

### Phase 5: Integration into ToolCallOrchestrator (TDD)

**Objective**: Integrate parallel execution into the main orchestrator while maintaining backward compatibility.

**TDD Steps**:
1. **RED**: Write integration specs for orchestrator
   - Test: Single tool call works with new system
   - Test: Multiple independent tools execute in parallel
   - Test: Dependent tools execute in correct order
   - Test: Tool results saved to history in correct order
   - Test: Tool results displayed in correct order
   - Test: Messages list updated correctly
   - Commit: "Add failing integration specs for parallel orchestrator"

2. **GREEN**: Integrate DependencyAnalyzer into orchestrator
   - Update `handle_tool_calls` to use DependencyAnalyzer
   - Keep sequential execution for now
   - Verify batches are created correctly
   - Run tests until green
   - Commit: "Integrate DependencyAnalyzer into orchestrator"

3. **GREEN**: Integrate ParallelExecutor into orchestrator
   - Replace sequential loop with batch execution
   - Use ParallelExecutor for each batch
   - Process results in order
   - Run tests until green
   - Commit: "Integrate ParallelExecutor into orchestrator"

4. **RED**: Write specs for thread-safe history access
   - Test: Multiple tools saving results concurrently
   - Test: History.add_message is thread-safe
   - Test: No data corruption or race conditions
   - Commit: "Add failing specs for concurrent history access"

5. **GREEN**: Implement thread-safe history access
   - Add mutex to History for add_message if needed
   - Verify ConsoleIO output queue handles concurrent puts
   - Run tests until green
   - Commit: "Ensure thread-safe history and console access"

6. **REFACTOR**: Update all orchestrator specs
   - Update existing specs to work with new architecture
   - Add specs for metrics tracking with parallel execution
   - Add specs for error handling in parallel context
   - Run full test suite + coverage
   - Commit: "Update and expand orchestrator specs"

**Acceptance Criteria**:
- [ ] ToolCallOrchestrator uses DependencyAnalyzer and ParallelExecutor
- [ ] All existing orchestrator tests pass
- [ ] Tool results saved and displayed in correct order
- [ ] Metrics tracking works correctly
- [ ] History and ConsoleIO are thread-safe
- [ ] 100% test coverage maintained
- [ ] Zero rubocop violations

**Estimated Commits**: 6-7

---

### Phase 6: End-to-End Testing & Validation (TDD)

**Objective**: Comprehensive integration testing and validation of the complete parallel execution system.

**TDD Steps**:
1. **RED**: Write end-to-end integration specs
   - Test: Complete chat loop with parallel tool calls
   - Test: Complex scenario: 10 tools with mixed dependencies
   - Test: Verify actual parallelism (timing-based)
   - Test: Error in one tool doesn't affect others in batch
   - Commit: "Add failing end-to-end integration specs"

2. **GREEN**: Fix integration issues
   - Debug and fix any issues revealed by integration tests
   - Verify all components work together
   - Run tests until green
   - Commit: "Fix integration issues for end-to-end tests"

3. **RED**: Write specs for edge cases
   - Test: All tools in single batch (all independent reads)
   - Test: All tools in separate batches (chain of dependencies)
   - Test: ExecuteBash in middle of tool sequence
   - Test: Empty tool_calls array
   - Test: Tool execution timeout during parallel execution
   - Commit: "Add failing specs for edge cases"

4. **GREEN**: Handle all edge cases
   - Fix any edge case failures
   - Add defensive code as needed
   - Run tests until green
   - Commit: "Handle edge cases in parallel execution"

5. **REFACTOR**: Code cleanup and documentation
   - Add inline documentation to all new classes
   - Add examples to class-level docs
   - Remove any dead code or debug statements
   - Run full test suite + coverage + lint
   - Commit: "Add documentation and clean up code"

**Acceptance Criteria**:
- [ ] Full integration tests pass
- [ ] All edge cases handled correctly
- [ ] Code is well-documented
- [ ] 100% test coverage maintained
- [ ] Zero rubocop violations
- [ ] All existing tests still pass

**Estimated Commits**: 5-6

---

### Phase 7: Performance Benchmarking

**Objective**: Validate performance improvements and document results.

**TDD Steps**:
1. **Create benchmark suite**
   - Create `spec/benchmarks/parallel_execution_benchmark.rb`
   - Benchmark: 5 independent FileRead tools
   - Benchmark: 10 independent FileRead tools
   - Benchmark: Mixed read/write dependencies
   - Run and collect baseline metrics
   - Commit: "Add performance benchmark suite"

2. **Document results**
   - Create `docs/parallel-execution-performance.md`
   - Document speedup ratios for different scenarios
   - Document overhead for single tool calls
   - Document batch configuration recommendations
   - Commit: "Document parallel execution performance results"

**Acceptance Criteria**:
- [ ] Benchmark suite exists and is runnable
- [ ] Performance improvements documented
- [ ] Recommendations for usage documented

**Estimated Commits**: 2

---

## Quality Gates (Every Commit)

Before each commit, verify:
```bash
# Run full test suite
bundle exec rspec

# Check coverage (must be 100% for new code)
open coverage/index.html

# Run linter
bundle exec rubocop

# Verify no warnings
bundle exec rubocop --format offenses
```

All must pass before committing.

## Total Estimated Commits

- Phase 1: 5-6 commits
- Phase 2: 5-6 commits
- Phase 3: 7-8 commits
- Phase 4: 9-10 commits
- Phase 5: 6-7 commits
- Phase 6: 5-6 commits
- Phase 7: 2 commits

**Total: 39-45 commits**

## Additional Enhancements
Beyond parallel execution, other optimizations could be explored:
1. **Batch Processing**: Modify tools to accept batch inputs where applicable (e.g., `file_read` could read multiple files in one call). This would require updates to tool definitions and the registry.
2. **Tool-Specific Caching**: Add caching logic at the registry level or within individual tools to store results of frequent operations.

## Feedback and Refinement
This plan is a comprehensive blueprint for parallel tool execution. Feedback is welcome on:
- Dependency analysis and batching logic for edge cases (e.g., dynamic paths, non-file resources).
- Thread safety mechanisms for shared state and integration with background workers.
- Prioritization of this optimization versus other enhancements like batch processing or caching.

**Last Updated**: October 31, 2025 - Added comprehensive TDD implementation plan with 7 phases
