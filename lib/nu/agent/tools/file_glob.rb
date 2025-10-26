# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileGlob
        def name
          "file_glob"
        end

        def description
          "PREFERRED tool for finding files by name/pattern. Use this instead of execute_bash with find/ls commands. " \
          "Returns structured JSON array of file paths, sorted by modification time (most recent first) by default. " \
          "Perfect for navigating unfamiliar codebases and discovering files.\n" \
          "\nPattern examples:\n" \
          "- '**/*.rb' - All Ruby files recursively\n" \
          "- '*.json' - JSON files in current directory\n" \
          "- 'lib/**/*.{rb,rake}' - Ruby and Rake files in lib/\n" \
          "- '**/test_*.rb' - All test files\n" \
          "\nCommon use cases: Find test files, locate config files, discover all files of a type, " \
          "find recently modified files (sorted by mtime), explore project structure. " \
          "Use file_grep instead if you need to search file CONTENTS."
        end

        def parameters
          {
            pattern: {
              type: "string",
              description: "Glob pattern to match files (e.g., '**/*.rb', 'lib/**/*.{rb,rake}', '*.json')",
              required: true
            },
            path: {
              type: "string",
              description: "Base directory to search from (defaults to current directory '.')",
              required: false
            },
            limit: {
              type: "integer",
              description: "Maximum number of results to return (defaults to 100)",
              required: false
            },
            sort_by: {
              type: "string",
              description: "How to sort results: 'mtime' (modification time, newest first), 'name' (alphabetical), or 'none' (default: 'mtime')",
              required: false
            }
          }
        end

        def execute(arguments:, history:, context:)
          pattern = arguments[:pattern] || arguments["pattern"]
          base_path = arguments[:path] || arguments["path"] || "."
          limit = arguments[:limit] || arguments["limit"] || 100
          sort_by = arguments[:sort_by] || arguments["sort_by"] || "mtime"

          # Validate required parameters
          if pattern.nil? || pattern.empty?
            return {
              error: "pattern is required",
              files: []
            }
          end

          # Build full glob pattern
          full_pattern = File.join(base_path, pattern)

          # Debug output
          if application = context['application']

            buffer = Nu::Agent::OutputBuffer.new
            buffer.debug("[file_glob] pattern: #{full_pattern}")

            buffer.debug("[file_glob] sort_by: #{sort_by}, limit: #{limit}")

            application.output.flush_buffer(buffer)
          end

          begin
            # Find matching files (excluding directories)
            files = Dir.glob(full_pattern, File::FNM_PATHNAME).select { |f| File.file?(f) }

            # Sort results
            sorted_files = case sort_by
            when "mtime"
              files.sort_by { |f| -File.mtime(f).to_i }  # Negative for descending order
            when "name"
              files.sort
            when "none"
              files
            else
              # Default to mtime if invalid sort_by
              files.sort_by { |f| -File.mtime(f).to_i }
            end

            # Limit results
            limited_files = sorted_files.take(limit)

            # Build result with metadata
            {
              files: limited_files,
              count: limited_files.length,
              total_matches: files.length,
              truncated: files.length > limit
            }

          rescue Errno::ENOENT => e
            {
              error: "Path not found: #{base_path}",
              files: []
            }
          rescue StandardError => e
            {
              error: "Glob failed: #{e.message}",
              files: []
            }
          end
        end
      end
    end
  end
end
