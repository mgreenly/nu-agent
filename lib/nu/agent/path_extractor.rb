# frozen_string_literal: true

module Nu
  module Agent
    # PathExtractor is responsible for extracting file/directory paths from tool arguments.
    #
    # This class serves as a critical component in the parallel tool execution system by identifying
    # which files and directories are affected by each tool operation. This information is used by
    # the DependencyAnalyzer to determine which tool calls can safely run in parallel.
    #
    # The extractor knows about three categories of tools:
    #
    # 1. **File-based tools**: Tools that operate on specific file paths (file_read, file_write, etc.)
    #    Returns an array of file paths that will be accessed.
    #
    # 2. **Unconfined tools**: Tools that can affect any resource (execute_bash, execute_python)
    #    Returns nil to signal that these tools must run in isolation.
    #
    # 3. **Non-file tools**: Tools that operate on non-file resources (database_query, search_internet)
    #    Returns nil as these don't conflict with file operations.
    #
    # Path Normalization:
    # The extractor normalizes all paths to absolute form using File.expand_path. This ensures that
    # relative paths like "./file.txt", "../file.txt", and "file.txt" are all properly resolved to
    # their absolute locations, allowing accurate dependency detection.
    #
    # Return Values:
    # - Array of paths: Tool operates on specific file/directory paths
    # - Empty array: Tool is file-based but has no paths (e.g., file_glob with just a pattern)
    # - nil: Tool is unconfined or operates on non-file resources
    #
    # Examples:
    #   extractor = PathExtractor.new
    #
    #   # File-based tool with single path
    #   extractor.extract("file_read", { file: "/path/to/file.rb" })
    #   # => ["/path/to/file.rb"]
    #
    #   # File-based tool with multiple paths
    #   extractor.extract("file_copy", { source: "/src.rb", destination: "/dst.rb" })
    #   # => ["/src.rb", "/dst.rb"]
    #
    #   # Unconfined tool (must run in isolation)
    #   extractor.extract("execute_bash", { command: "ls" })
    #   # => nil
    #
    #   # Path normalization
    #   extractor.extract_and_normalize("file_read", { file: "../file.rb" })
    #   # => ["/absolute/path/to/file.rb"]
    class PathExtractor
      # File-based tools and their path parameter names
      #
      # Maps tool names to the parameter names that contain file paths.
      # Tools with empty arrays are file-related but don't operate on specific paths
      # (e.g., file_glob searches by pattern, not a specific file).
      FILE_TOOLS = {
        "file_read" => [:file],
        "file_write" => [:file],
        "file_edit" => [:file],
        "file_delete" => [:file],
        "file_copy" => %i[source destination],
        "file_move" => %i[source destination],
        "file_stat" => [:file],
        "file_glob" => [], # Uses pattern, not a specific path
        "file_grep" => [], # Searches content, not a specific path operation
        "file_tree" => [:path]
      }.freeze

      # Directory-based tools and their path parameter names
      #
      # Similar to FILE_TOOLS but for directory operations.
      DIR_TOOLS = {
        "dir_list" => [:path],
        "dir_create" => [:path],
        "dir_delete" => [:path],
        "dir_tree" => [:path]
      }.freeze

      # Tools that have unconfined scope and should return nil
      #
      # These tools can potentially affect any file or resource in the system,
      # so they must run in isolation as barriers. The extractor returns nil
      # for these tools to signal to the DependencyAnalyzer that they need
      # special handling.
      UNCONFINED_TOOLS = %w[
        execute_bash
        execute_python
      ].freeze

      # Tools that operate on non-file resources (databases, network, etc.)
      #
      # These tools don't operate on the file system, so they don't participate
      # in file-based dependency analysis. Returns nil to indicate no file paths.
      NON_FILE_TOOLS = %w[
        database_query
        database_schema
        database_tables
        database_message
        search_internet
        agent_summarizer
      ].freeze

      # Extract file/directory paths from tool arguments
      #
      # @param tool_name [String] The name of the tool
      # @param arguments [Hash] The tool's arguments (can use symbol or string keys)
      # @return [Array<String>, nil] Array of paths, empty array if no paths found, or nil for unconfined/non-file tools
      def extract(tool_name, arguments)
        # Return nil for unconfined tools (they need to run in isolation)
        return nil if UNCONFINED_TOOLS.include?(tool_name)

        # Return nil for non-file resource tools
        return nil if NON_FILE_TOOLS.include?(tool_name)

        # Return empty array if arguments are nil or not a hash
        return [] if arguments.nil? || !arguments.is_a?(Hash)

        # Get the path parameter names for this tool
        path_params = FILE_TOOLS[tool_name] || DIR_TOOLS[tool_name]

        # Return nil for unknown tools
        return nil if path_params.nil?

        # Return empty array if tool has no path parameters (like file_glob, file_grep)
        return [] if path_params.empty?

        # Extract paths from arguments
        path_params.map do |param|
          # Try both symbol and string keys
          arguments[param] || arguments[param.to_s]
        end.compact
      end

      # Extract and normalize file/directory paths from tool arguments
      #
      # This method extracts paths and converts them to absolute, normalized form.
      # Relative paths are resolved against the current working directory.
      # Path normalization handles:
      # - Converting relative to absolute paths
      # - Resolving . (current directory) and .. (parent directory) references
      # - Removing duplicate slashes
      #
      # @param tool_name [String] The name of the tool
      # @param arguments [Hash] The tool's arguments (can use symbol or string keys)
      # @return [Array<String>, nil] Array of normalized absolute paths, empty array if no paths,
      #   or nil for unconfined/non-file tools
      def extract_and_normalize(tool_name, arguments)
        paths = extract(tool_name, arguments)

        # Return nil if extract returned nil (unconfined or non-file tools)
        return nil if paths.nil?

        # Return empty array if extract returned empty array
        return [] if paths.empty?

        # Normalize each path and filter out nil/empty values
        paths.map do |path|
          next if path.nil? || path.empty?

          # Use File.expand_path to normalize the path
          # This handles:
          # - Converting relative to absolute paths
          # - Resolving . and .. references
          # - Removing duplicate slashes
          File.expand_path(path)
        end.compact
      end
    end
  end
end
