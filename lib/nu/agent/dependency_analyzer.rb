# frozen_string_literal: true

require "json"

module Nu
  module Agent
    # DependencyAnalyzer analyzes tool calls and groups them into batches that can be executed in parallel.
    # Tool calls within a batch are independent and can run concurrently.
    # Batches must be executed sequentially to maintain dependencies.
    #
    # Dependency Rules:
    # - Read operations on different paths can run in parallel
    # - Read operations on the same path can run in parallel
    # - Write operations block subsequent operations on the same path
    # - Unconfined write operations (e.g., execute_bash) must run in isolation
    #
    # Examples:
    #   analyzer = DependencyAnalyzer.new
    #   batches = analyzer.analyze(tool_calls)
    #   # => [[tool1, tool2], [tool3], [tool4, tool5]]
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
      def can_batch_tool?(tool_call, current_batch, path_writes)
        return true if current_batch.empty?

        tool_info = extract_tool_info(tool_call)

        # Unconfined write tools must run in isolation
        return false if unconfined_write?(tool_info)

        # Cannot batch with an unconfined write tool
        return false if current_batch.any? { |tc| unconfined_write?(extract_tool_info(tc)) }

        !path_conflict?(tool_info, current_batch, path_writes)
      end

      # Add a tool to the current batch and track writes
      def add_to_batch(current_batch, tool_call, path_writes)
        current_batch << tool_call
        track_write_paths(tool_call, path_writes)
      end

      # Start a new batch
      def start_new_batch(batches, current_batch, tool_call, path_writes)
        batches << current_batch unless current_batch.empty?
        track_write_paths(tool_call, path_writes)
      end

      # Extract tool information (name, arguments, metadata, paths)
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
      def default_metadata
        { operation_type: :read, scope: :confined }
      end

      # Check if a tool is an unconfined write operation (barrier)
      def unconfined_write?(tool_info)
        tool_info[:operation_type] == :write && tool_info[:scope] == :unconfined
      end

      # Check if tool has a path conflict with current batch
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
      def write_conflicts?(affected_paths, current_batch)
        affected_paths.any? { |path| path_in_current_batch?(current_batch, path) }
      end

      # Check if read operation conflicts with prior writes
      def read_conflicts?(affected_paths, current_batch, path_writes)
        affected_paths.any? do |path|
          path_writes[path] && path_in_current_batch?(current_batch, path)
        end
      end

      # Track write paths for a tool call
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
