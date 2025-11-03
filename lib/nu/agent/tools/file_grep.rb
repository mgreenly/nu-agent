# frozen_string_literal: true

require "json"
require_relative "../subsystem_debugger"
require_relative "file_grep/output_parser"

module Nu
  module Agent
    module Tools
      class FileGrep
        PARAMETERS = {
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
            description: "Output format: 'files_with_matches' (just file paths), " \
                         "'content' (matching lines with context), or 'count' (match counts). " \
                         "Default: 'files_with_matches'",
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
        }.freeze

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
          PARAMETERS
        end

        def operation_type
          :read
        end

        def scope
          :confined
        end

        def execute(arguments:, **context)
          args = parse_arguments(arguments)

          error_response = validate_arguments(args)
          return error_response if error_response

          cmd = build_ripgrep_command(
            pattern: args[:pattern],
            path: args[:path],
            output_mode: args[:output_mode],
            glob: args[:glob],
            case_insensitive: args[:case_insensitive],
            context_before: args[:context_before],
            context_after: args[:context_after],
            context: args[:context_both],
            max_results: args[:max_results]
          )

          log_command_debug(cmd, context)

          result = execute_ripgrep(cmd, args[:output_mode], args[:max_results])

          log_stats_debug(result, args[:output_mode], context)

          result
        end

        private

        def parse_arguments(arguments)
          {
            pattern: get_arg(arguments, :pattern),
            path: get_arg(arguments, :path, "."),
            output_mode: get_arg(arguments, :output_mode, "files_with_matches"),
            glob: get_arg(arguments, :glob),
            case_insensitive: get_arg(arguments, :case_insensitive, false),
            context_before: get_arg(arguments, :context_before),
            context_after: get_arg(arguments, :context_after),
            context_both: get_arg(arguments, :context),
            max_results: get_arg(arguments, :max_results, 100)
          }
        end

        def get_arg(arguments, key, default = nil)
          arguments[key] || arguments[key.to_s] || default
        end

        def validate_arguments(args)
          return validate_pattern(args[:pattern]) if args[:pattern].nil? || args[:pattern].empty?
          return validate_output_mode(args[:output_mode]) unless valid_output_mode?(args[:output_mode])

          nil
        end

        def validate_pattern(_pattern)
          {
            error: "pattern is required",
            matches: []
          }
        end

        def validate_output_mode(_output_mode)
          {
            error: "output_mode must be 'files_with_matches', 'content', or 'count'",
            matches: []
          }
        end

        def valid_output_mode?(output_mode)
          %w[files_with_matches content count].include?(output_mode)
        end

        def log_command_debug(cmd, context)
          application = context[:application]
          return unless application

          SubsystemDebugger.debug_output(
            application,
            "search",
            "command: #{cmd.join(' ')}",
            level: 1
          )
        end

        def log_stats_debug(result, output_mode, context)
          application = context[:application]
          return unless application
          return if result.key?(:error)

          case output_mode
          when "files_with_matches"
            log_files_stats(application, result)
          when "count"
            log_count_stats(application, result)
          when "content"
            log_content_stats(application, result)
          else
            # output_mode is validated earlier, so this should not occur
            # but handle gracefully if it somehow does
            false
          end
        end

        def log_files_stats(application, result)
          SubsystemDebugger.debug_output(
            application,
            "search",
            "found #{result[:count]} files with matches",
            level: 2
          )
        end

        def log_count_stats(application, result)
          SubsystemDebugger.debug_output(
            application,
            "search",
            "found #{result[:total_matches]} matches in #{result[:total_files]} files",
            level: 2
          )
        end

        def log_content_stats(application, result)
          message = "found #{result[:count]} matches"
          message += " (truncated)" if result[:truncated]

          SubsystemDebugger.debug_output(
            application,
            "search",
            message,
            level: 2
          )
        end

        def execute_ripgrep(cmd, output_mode, max_results)
          stdout, stderr, status = Open3.capture3(*cmd)

          return handle_ripgrep_error(stderr) if status.exitstatus > 1

          output_parser.parse_output(stdout, output_mode, max_results)
        rescue StandardError => e
          {
            error: "Search failed: #{e.message}",
            matches: []
          }
        end

        def output_parser
          @output_parser ||= OutputParser.new
        end

        def handle_ripgrep_error(stderr)
          {
            error: "ripgrep failed: #{stderr}",
            matches: []
          }
        end

        def build_ripgrep_command(pattern:, path:, output_mode:, **options)
          cmd_parts = ["rg"]

          add_output_mode_flags(cmd_parts, output_mode)
          add_case_sensitivity_flag(cmd_parts, options)
          add_context_flags(cmd_parts, output_mode, options)
          add_filtering_flags(cmd_parts, options)
          add_pattern_and_path(cmd_parts, pattern, path)

          cmd_parts
        end

        def add_output_mode_flags(cmd_parts, output_mode)
          case output_mode
          when "files_with_matches"
            cmd_parts << "--files-with-matches"
          when "count"
            cmd_parts << "--count"
          when "content"
            cmd_parts << "--json"
            cmd_parts << "--line-number"
          else
            # output_mode is validated earlier, so this should not occur
            # Return empty to allow command to continue (ripgrep will use default behavior)
            []
          end
        end

        def add_case_sensitivity_flag(cmd_parts, options)
          cmd_parts << "-i" if options[:case_insensitive]
        end

        def add_context_flags(cmd_parts, output_mode, options)
          return unless output_mode == "content"

          if options[:context]
            cmd_parts << "-C" << options[:context].to_s
          else
            cmd_parts << "-B" << options[:context_before].to_s if options[:context_before]
            cmd_parts << "-A" << options[:context_after].to_s if options[:context_after]
          end
        end

        def add_filtering_flags(cmd_parts, options)
          cmd_parts << "--glob" << options[:glob] if options[:glob]
          cmd_parts << "--max-count" << options[:max_results].to_s
        end

        def add_pattern_and_path(cmd_parts, pattern, path)
          # Pattern and path - double dash separates pattern from paths
          cmd_parts << "--" << pattern << path
        end
      end
    end
  end
end
