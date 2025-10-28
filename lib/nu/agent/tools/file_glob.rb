# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileGlob
        PARAMETERS = {
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
            description: "How to sort results: 'mtime' (modification time, newest first), " \
                         "'name' (alphabetical), or 'none' (default: 'mtime')",
            required: false
          }
        }.freeze

        def name
          "file_glob"
        end

        def description
          "PREFERRED tool for finding files by name/pattern. " \
            "Use this instead of execute_bash with find/ls commands. " \
            "Returns structured JSON array of file paths, " \
            "sorted by modification time (most recent first) by default. " \
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
          PARAMETERS
        end

        def execute(arguments:, **)
          args = parse_arguments(arguments)

          return error_response("pattern is required") if args[:pattern].nil? || args[:pattern].empty?

          begin
            files = find_matching_files(args[:pattern], args[:base_path])
            sorted_files = sort_files(files, args[:sort_by])
            limited_files = sorted_files.take(args[:limit])

            build_success_response(limited_files, files.length, args[:limit])
          rescue Errno::ENOENT
            error_response("Path not found: #{args[:base_path]}")
          rescue StandardError => e
            error_response("Glob failed: #{e.message}")
          end
        end

        private

        def parse_arguments(arguments)
          {
            pattern: arguments[:pattern] || arguments["pattern"],
            base_path: arguments[:path] || arguments["path"] || ".",
            limit: arguments[:limit] || arguments["limit"] || 100,
            sort_by: arguments[:sort_by] || arguments["sort_by"] || "mtime"
          }
        end

        def error_response(message)
          { error: message, files: [] }
        end

        def find_matching_files(pattern, base_path)
          full_pattern = File.join(base_path, pattern)
          Dir.glob(full_pattern, File::FNM_PATHNAME).select { |f| File.file?(f) }
        end

        def sort_files(files, sort_by)
          case sort_by
          when "name" then files.sort
          when "none" then files
          else
            files.sort_by { |f| -File.mtime(f).to_i }
          end
        end

        def build_success_response(limited_files, total_matches, limit)
          {
            files: limited_files,
            count: limited_files.length,
            total_matches: total_matches,
            truncated: total_matches > limit
          }
        end
      end
    end
  end
end
