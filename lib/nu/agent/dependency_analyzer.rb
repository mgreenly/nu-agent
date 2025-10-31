# frozen_string_literal: true

require "json"

module Nu
  module Agent
    # DependencyAnalyzer analyzes tool calls and groups them into batches that can be executed in parallel.
    #
    # This class implements a dependency analysis algorithm that determines which tool calls can be safely
    # executed concurrently and which must be executed sequentially. The goal is to maximize parallelism
    # while maintaining data consistency and safety.
    #
    # Tool calls within a batch are independent and can run concurrently.
    # Batches must be executed sequentially to maintain dependencies.
    #
    # Dependency Rules:
    # - Read operations on different paths can run in parallel
    # - Read operations on the same path can run in parallel (reads don't conflict)
    # - Write operations block subsequent operations on the same path (read-after-write, write-after-write)
    # - Unconfined write operations (e.g., execute_bash) must run in isolation as a barrier
    #
    # Algorithm:
    # 1. Iterate through tool calls in order
    # 2. For each tool call, determine if it can be added to the current batch
    # 3. If it can be added (no conflicts), add it to current batch
    # 4. If it cannot (has conflicts), finalize current batch and start a new one
    # 5. Track write operations per path to detect read-after-write dependencies
    #
    # Examples:
    #   analyzer = DependencyAnalyzer.new
    #   batches = analyzer.analyze(tool_calls)
    #   # => [[tool1, tool2], [tool3], [tool4, tool5]]
    #
    #   # Example scenario:
    #   # tool_calls = [
    #   #   { function: { name: "file_read", arguments: { file: "a.txt" } } },     # Batch 1
    #   #   { function: { name: "file_read", arguments: { file: "b.txt" } } },     # Batch 1 (parallel)
    #   #   { function: { name: "file_write", arguments: { file: "a.txt" } } },    # Batch 2 (conflicts with batch 1)
    #   #   { function: { name: "execute_bash", arguments: { command: "ls" } } },  # Batch 3 (barrier)
    #   #   { function: { name: "file_read", arguments: { file: "c.txt" } } }      # Batch 4
    #   # ]
    #   # Results in 4 batches: [[read a, read b], [write a], [bash], [read c]]
    class DependencyAnalyzer
      def initialize(tool_registry: nil, path_extractor: nil)
        @tool_registry = tool_registry || ToolRegistry.new
        @path_extractor = path_extractor || PathExtractor.new
      end

      # Analyze tool calls and group them into parallelizable batches
      #
      # @param tool_calls [Array<Hash>] Array of tool call hashes from the API response
      # @return [Array<Array<Hash>>] Array of batches, where each batch is an array of tool calls
      def analyze(tool_calls)
        return [] if tool_calls.nil? || tool_calls.empty?

        batches = []
        current_batch = []
        path_writes = {} # Track last write operation per path

        tool_calls.each do |tool_call|
          can_batch = can_batch_tool?(tool_call, current_batch, path_writes)

          if can_batch
            add_to_batch(current_batch, tool_call, path_writes)
          else
            start_new_batch(batches, current_batch, tool_call, path_writes)
            current_batch = [tool_call]
          end
        end

        # Add the last batch if it has any tool calls
        batches << current_batch unless current_batch.empty?

        batches
      end

      private

      # Check if a tool can be batched with current batch
      #
      # A tool can be batched if:
      # 1. The current batch is empty (first tool in batch), OR
      # 2. The tool is not an unconfined write (barrier), AND
      # 3. The current batch doesn't contain an unconfined write, AND
      # 4. The tool doesn't have path conflicts with the current batch
      #
      # @param tool_call [Hash] Tool call to check
      # @param current_batch [Array<Hash>] Current batch of tool calls
      # @param path_writes [Hash] Map of paths to their last write operation
      # @return [Boolean] true if tool can be added to current batch
      def can_batch_tool?(tool_call, current_batch, path_writes)
        return true if current_batch.empty?

        tool_info = extract_tool_info(tool_call)

        # Unconfined write tools must run in isolation (barrier synchronization)
        return false if unconfined_write?(tool_info)

        # Cannot batch with an unconfined write tool (barrier prevents batching)
        return false if current_batch.any? { |tc| unconfined_write?(extract_tool_info(tc)) }

        # Check for path conflicts with current batch
        !path_conflict?(tool_info, current_batch, path_writes)
      end

      # Add a tool to the current batch and track writes
      #
      # @param current_batch [Array<Hash>] Current batch to add tool to
      # @param tool_call [Hash] Tool call to add
      # @param path_writes [Hash] Map of paths to track write operations
      def add_to_batch(current_batch, tool_call, path_writes)
        current_batch << tool_call
        track_write_paths(tool_call, path_writes)
      end

      # Start a new batch and track write operations
      #
      # Finalizes the current batch (if non-empty) and prepares for a new batch.
      # Also tracks any write operations from the tool call that starts the new batch.
      #
      # @param batches [Array<Array<Hash>>] Array of completed batches
      # @param current_batch [Array<Hash>] Current batch to finalize
      # @param tool_call [Hash] Tool call that starts the new batch
      # @param path_writes [Hash] Map of paths to track write operations
      def start_new_batch(batches, current_batch, tool_call, path_writes)
        batches << current_batch unless current_batch.empty?
        track_write_paths(tool_call, path_writes)
      end

      # Extract tool information (name, arguments, metadata, paths)
      #
      # Gathers all relevant information about a tool call needed for dependency analysis:
      # - Operation type (read/write)
      # - Scope (confined/unconfined)
      # - Affected paths (normalized file paths)
      #
      # @param tool_call [Hash] Tool call hash from API response
      # @return [Hash] Hash with :operation_type, :scope, and :affected_paths keys
      def extract_tool_info(tool_call)
        tool_name = tool_call.dig("function", "name")
        arguments = parse_arguments(tool_call.dig("function", "arguments"))
        metadata = @tool_registry.metadata_for(tool_name) || default_metadata
        affected_paths = @path_extractor.extract_and_normalize(tool_name, arguments) || []

        {
          operation_type: metadata[:operation_type],
          scope: metadata[:scope],
          affected_paths: affected_paths
        }
      end

      # Default metadata for unknown tools
      #
      # Conservative default: treat unknown tools as read operations with confined scope.
      # This prevents accidental parallelization of potentially unsafe operations.
      #
      # @return [Hash] Default metadata with :operation_type and :scope
      def default_metadata
        { operation_type: :read, scope: :confined }
      end

      # Check if a tool is an unconfined write operation (barrier)
      #
      # Unconfined write operations (like execute_bash) can affect any file or resource,
      # so they must run in isolation as a barrier to ensure safety.
      #
      # @param tool_info [Hash] Tool information with :operation_type and :scope
      # @return [Boolean] true if tool is an unconfined write operation
      def unconfined_write?(tool_info)
        tool_info[:operation_type] == :write && tool_info[:scope] == :unconfined
      end

      # Check if tool has a path conflict with current batch
      #
      # A path conflict occurs when:
      # - A write operation affects a path already in the current batch (any operation)
      # - A read operation affects a path that has a pending write in the current batch
      #
      # @param tool_info [Hash] Tool information with :operation_type and :affected_paths
      # @param current_batch [Array<Hash>] Current batch of tool calls
      # @param path_writes [Hash] Map of paths to their last write operation
      # @return [Boolean] true if there's a path conflict
      def path_conflict?(tool_info, current_batch, path_writes)
        operation_type = tool_info[:operation_type]
        affected_paths = tool_info[:affected_paths]

        if operation_type == :write
          write_conflicts?(affected_paths, current_batch)
        elsif operation_type == :read
          read_conflicts?(affected_paths, current_batch, path_writes)
        else
          false
        end
      end

      # Check if write operation conflicts with current batch
      #
      # A write conflicts if any of its affected paths are already being accessed
      # by tools in the current batch (either read or write operations).
      #
      # @param affected_paths [Array<String>] Paths affected by the write operation
      # @param current_batch [Array<Hash>] Current batch of tool calls
      # @return [Boolean] true if there's a conflict
      def write_conflicts?(affected_paths, current_batch)
        affected_paths.any? { |path| path_in_current_batch?(current_batch, path) }
      end

      # Check if read operation conflicts with prior writes
      #
      # A read conflicts if it accesses a path that has a pending write operation
      # in the current batch (read-after-write dependency).
      #
      # @param affected_paths [Array<String>] Paths to be read
      # @param current_batch [Array<Hash>] Current batch of tool calls
      # @param path_writes [Hash] Map of paths to their last write operation
      # @return [Boolean] true if there's a read-after-write conflict
      def read_conflicts?(affected_paths, current_batch, path_writes)
        affected_paths.any? do |path|
          path_writes[path] && path_in_current_batch?(current_batch, path)
        end
      end

      # Track write paths for a tool call
      #
      # Records all paths affected by write operations to detect read-after-write
      # and write-after-write dependencies.
      #
      # @param tool_call [Hash] Tool call to track
      # @param path_writes [Hash] Map of paths to track write operations
      def track_write_paths(tool_call, path_writes)
        tool_info = extract_tool_info(tool_call)
        return unless tool_info[:operation_type] == :write

        tool_info[:affected_paths].each do |path|
          path_writes[path] = tool_call
        end
      end

      # Parse tool arguments from JSON string
      #
      # @param arguments [String, Hash] Tool arguments (JSON string or Hash)
      # @return [Hash] Parsed arguments
      def parse_arguments(arguments)
        return {} if arguments.nil?
        return arguments if arguments.is_a?(Hash)

        JSON.parse(arguments)
      rescue JSON::ParserError
        {}
      end

      # Check if a path is affected by any tool call in the current batch
      #
      # @param current_batch [Array<Hash>] Current batch of tool calls
      # @param path [String] Path to check
      # @return [Boolean] true if path is in current batch
      def path_in_current_batch?(current_batch, path)
        current_batch.any? do |tc|
          tool_name = tc.dig("function", "name")
          arguments = parse_arguments(tc.dig("function", "arguments"))
          paths = @path_extractor.extract_and_normalize(tool_name, arguments) || []
          paths.include?(path)
        end
      end
    end
  end
end
