# frozen_string_literal: true

require 'json'

module Nu
  module Agent
    module Tools
      class FileGrep
        def name
          "file_grep"
        end

        def description
          "PREFERRED tool for searching code patterns. Use this instead of execute_bash with grep/rg commands. " \
          "Returns structured JSON (no parsing needed) with file paths and line numbers for easy code references. " \
          "Supports regex patterns, file filtering (glob), case-insensitive search, and context lines. " \
          "\n\nThree output modes:\n" \
          "- 'files_with_matches' (default): Quick discovery - which files contain this pattern? " \
          "Example: Find all files importing a module.\n" \
          "- 'content': Detailed view - show actual matching lines with line numbers. " \
          "Example: Find function definitions with 'def execute'.\n" \
          "- 'count': Statistics - how many matches per file? " \
          "Example: Count TODO comments across the codebase.\n" \
          "\nCommon use cases: Find function/class definitions, search for TODO/FIXME comments, " \
          "locate error handling code, find imports/requires, search API usage patterns."
        end

        def parameters
          {
            pattern: {
              type: "string",
              description: "Regex pattern to search for (e.g., 'def execute', 'class.*Tool', 'TODO:')",
              required: true
            },
            path: {
              type: "string",
              description: "Directory or file to search in (defaults to current directory '.')",
              required: false
            },
            output_mode: {
              type: "string",
              description: "Output format: 'files_with_matches' (just file paths), 'content' (matching lines with context), or 'count' (match counts). Default: 'files_with_matches'",
              required: false
            },
            glob: {
              type: "string",
              description: "Filter files by glob pattern (e.g., '*.rb', '*.{js,ts}')",
              required: false
            },
            case_insensitive: {
              type: "boolean",
              description: "Perform case-insensitive search (default: false)",
              required: false
            },
            context_before: {
              type: "integer",
              description: "Number of lines to show before each match (only for 'content' mode)",
              required: false
            },
            context_after: {
              type: "integer",
              description: "Number of lines to show after each match (only for 'content' mode)",
              required: false
            },
            context: {
              type: "integer",
              description: "Number of lines to show before AND after each match (only for 'content' mode)",
              required: false
            },
            max_results: {
              type: "integer",
              description: "Maximum number of results to return (default: 100)",
              required: false
            }
          }
        end

        def execute(arguments:, history:, context:)
          pattern = arguments[:pattern] || arguments["pattern"]
          path = arguments[:path] || arguments["path"] || "."
          output_mode = arguments[:output_mode] || arguments["output_mode"] || "files_with_matches"
          glob_pattern = arguments[:glob] || arguments["glob"]
          case_insensitive = arguments[:case_insensitive] || arguments["case_insensitive"] || false
          context_before = arguments[:context_before] || arguments["context_before"]
          context_after = arguments[:context_after] || arguments["context_after"]
          context_both = arguments[:context] || arguments["context"]
          max_results = arguments[:max_results] || arguments["max_results"] || 100

          # Validate required parameters
          if pattern.nil? || pattern.empty?
            return {
              error: "pattern is required",
              matches: []
            }
          end

          # Validate output_mode
          unless ["files_with_matches", "content", "count"].include?(output_mode)
            return {
              error: "output_mode must be 'files_with_matches', 'content', or 'count'",
              matches: []
            }
          end

          # Build ripgrep command
          cmd = build_ripgrep_command(
            pattern: pattern,
            path: path,
            output_mode: output_mode,
            glob: glob_pattern,
            case_insensitive: case_insensitive,
            context_before: context_before,
            context_after: context_after,
            context: context_both,
            max_results: max_results
          )

          # Debug output
          if application = context['application']
            application.output.debug("[file_grep] command: #{cmd.join(' ')}")
            application.output.debug("[file_grep] output_mode: #{output_mode}")
          end

          # Execute ripgrep
          begin
            stdout, stderr, status = Open3.capture3(*cmd)

            # Ripgrep returns exit code 1 when no matches found (not an error)
            if status.exitstatus > 1
              return {
                error: "ripgrep failed: #{stderr}",
                matches: []
              }
            end

            # Parse output based on mode
            result = case output_mode
            when "files_with_matches"
              parse_files_with_matches(stdout, max_results)
            when "count"
              parse_count(stdout, max_results)
            when "content"
              parse_content(stdout, max_results)
            end

            result
          rescue StandardError => e
            {
              error: "Search failed: #{e.message}",
              matches: []
            }
          end
        end

        private

        def build_ripgrep_command(pattern:, path:, output_mode:, glob:, case_insensitive:, context_before:, context_after:, context:, max_results:)
          cmd_parts = ["rg"]

          # Output mode specific flags
          case output_mode
          when "files_with_matches"
            cmd_parts << "--files-with-matches"
          when "count"
            cmd_parts << "--count"
          when "content"
            cmd_parts << "--json"
            cmd_parts << "--line-number"
          end

          # Case sensitivity
          cmd_parts << "-i" if case_insensitive

          # Context lines (only for content mode)
          if output_mode == "content"
            if context
              cmd_parts << "-C" << context.to_s
            else
              cmd_parts << "-B" << context_before.to_s if context_before
              cmd_parts << "-A" << context_after.to_s if context_after
            end
          end

          # File filtering
          cmd_parts << "--glob" << glob if glob

          # Max count per file (helps limit output)
          cmd_parts << "--max-count" << max_results.to_s

          # Pattern and path - double dash separates pattern from paths
          cmd_parts << "--" << pattern << path

          # Return array so Open3 can properly quote arguments
          cmd_parts
        end

        def parse_files_with_matches(stdout, max_results)
          files = stdout.split("\n").take(max_results)
          {
            files: files,
            count: files.length
          }
        end

        def parse_count(stdout, max_results)
          results = []
          stdout.split("\n").take(max_results).each do |line|
            # Format: "path/to/file:count"
            if line =~ /^(.+):(\d+)$/
              results << {
                file: $1,
                count: $2.to_i
              }
            end
          end

          {
            files: results,
            total_files: results.length,
            total_matches: results.sum { |r| r[:count] }
          }
        end

        def parse_content(stdout, max_results)
          matches = []
          current_match = nil

          stdout.each_line do |line|
            begin
              data = JSON.parse(line)

              case data["type"]
              when "match"
                match_data = data["data"]

                matches << {
                  file: match_data["path"]["text"],
                  line_number: match_data["line_number"],
                  line: match_data["lines"]["text"].chomp,
                  match_text: match_data["submatches"]&.first&.dig("match", "text")
                }

                break if matches.length >= max_results

              when "context"
                # Context lines could be added to the previous match if needed
                # For now, we'll skip them as ripgrep --json provides them separately
              end
            rescue JSON::ParserError
              # Skip non-JSON lines
            end
          end

          {
            matches: matches,
            count: matches.length,
            truncated: matches.length >= max_results
          }
        end
      end
    end
  end
end
