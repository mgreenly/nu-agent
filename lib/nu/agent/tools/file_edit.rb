# frozen_string_literal: true

require_relative "file_edit/replace_operation"
require_relative "file_edit/append_operation"
require_relative "file_edit/prepend_operation"
require_relative "file_edit/insert_after_operation"
require_relative "file_edit/insert_before_operation"
require_relative "file_edit/insert_line_operation"
require_relative "file_edit/replace_range_operation"

module Nu
  module Agent
    module Tools
      class FileEdit
        def name
          "file_edit"
        end

        def description
          "PREFERRED tool for editing files. Use exact string replacement instead of rewriting entire files. " \
            "Safer and more efficient than execute_bash with sed/awk commands. " \
            "Works perfectly with file_read: read to see line numbers, " \
            "then edit using line-based or string-based operations.\n" \
            "\nPrimary mode - Exact string replacement:\n" \
            "- Provide old_string and new_string for precise edits\n" \
            "- By default replaces first occurrence (safe)\n" \
            "- Use replace_all: true to replace all occurrences\n" \
            "- Returns error if old_string not found (read file first to verify)\n" \
            "\nLine-based editing (works with file_read line numbers):\n" \
            "- insert_line: Insert content at specific line number (1-indexed)\n" \
            "- replace_range_start + replace_range_end: Replace a range of lines (inclusive)\n" \
            "\nPattern-based insertion:\n" \
            "- insert_after: Insert content after first match of pattern\n" \
            "- insert_before: Insert content before first match of pattern\n" \
            "\nSimple operations:\n" \
            "- append: Add content to end of file\n" \
            "- prepend: Add content to beginning of file\n" \
            "\nAlways prefer targeted edits over file rewrites. This tool encourages best practices."
        end

        def parameters
          {
            file: {
              type: "string",
              description: "Path to the file (relative to project root or absolute within project)",
              required: true
            },
            old_string: {
              type: "string",
              description: "Exact text to find and replace (must match exactly including whitespace). " \
                           "Use with new_string.",
              required: false
            },
            new_string: {
              type: "string",
              description: "Replacement text. Use with old_string.",
              required: false
            },
            replace_all: {
              type: "boolean",
              description: "Replace all occurrences of old_string (default: false, only replaces first match)",
              required: false
            },
            append: {
              type: "string",
              description: "Content to append to end of file. Mutually exclusive with other operations.",
              required: false
            },
            prepend: {
              type: "string",
              description: "Content to prepend to beginning of file. Mutually exclusive with other operations.",
              required: false
            },
            insert_after: {
              type: "string",
              description: "Pattern to find. Will insert content after first match. Use with content parameter.",
              required: false
            },
            insert_before: {
              type: "string",
              description: "Pattern to find. Will insert content before first match. Use with content parameter.",
              required: false
            },
            content: {
              type: "string",
              description: "Content to insert when using insert_after, insert_before, insert_line, or replace_range.",
              required: false
            },
            insert_line: {
              type: "integer",
              description: "Line number to insert content at (1-indexed). " \
                           "Content will be inserted before this line. Use with content parameter.",
              required: false
            },
            replace_range_start: {
              type: "integer",
              description: "Starting line number for range replacement (1-indexed, inclusive). " \
                           "Use with replace_range_end and content.",
              required: false
            },
            replace_range_end: {
              type: "integer",
              description: "Ending line number for range replacement (1-indexed, inclusive). " \
                           "Use with replace_range_start and content.",
              required: false
            }
          }
        end

        def execute(arguments:, **)
          file_path = arguments[:file] || arguments["file"]
          return { status: "error", error: "file path is required" } if file_path.nil? || file_path.empty?

          # Create a base operation to use shared methods
          base_op = EditOperation.new
          resolved_path = base_op.resolve_path(file_path)
          base_op.validate_path(resolved_path)

          ops = parse_operations(arguments)
          strategy = select_strategy(ops)

          return error_no_operation unless strategy

          begin
            strategy.execute(resolved_path, ops)
          rescue StandardError => e
            { status: "error", error: e.message }
          end
        end

        private

        def parse_operations(arguments)
          {
            old_string: arguments[:old_string] || arguments["old_string"],
            new_string: arguments[:new_string] || arguments["new_string"],
            replace_all: arguments[:replace_all] || arguments["replace_all"] || false,
            append: arguments[:append] || arguments["append"],
            prepend: arguments[:prepend] || arguments["prepend"],
            pattern: arguments[:insert_after] || arguments["insert_after"] ||
              arguments[:insert_before] || arguments["insert_before"],
            insert_after: arguments[:insert_after] || arguments["insert_after"],
            insert_before: arguments[:insert_before] || arguments["insert_before"],
            content: arguments[:content] || arguments["content"],
            line_number: arguments[:insert_line] || arguments["insert_line"],
            start_line: arguments[:replace_range_start] || arguments["replace_range_start"],
            end_line: arguments[:replace_range_end] || arguments["replace_range_end"]
          }
        end

        def select_strategy(ops)
          return ReplaceOperation.new if ops[:old_string] && ops[:new_string]
          return AppendOperation.new if ops[:append]
          return PrependOperation.new if ops[:prepend]
          return InsertAfterOperation.new if ops[:insert_after]
          return InsertBeforeOperation.new if ops[:insert_before]
          return InsertLineOperation.new if ops[:line_number]
          return ReplaceRangeOperation.new if ops[:start_line] && ops[:end_line]

          nil
        end

        def error_no_operation
          {
            status: "error",
            error: "Must provide either: (old_string + new_string), append, prepend, " \
                   "(insert_after/insert_before + content), (insert_line + content), " \
                   "or (replace_range_start + replace_range_end + content)"
          }
        end
      end
    end
  end
end
