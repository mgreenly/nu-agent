# frozen_string_literal: true

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

          resolved_path = resolve_path(file_path)
          validate_path(resolved_path)

          ops = parse_operations(arguments)
          log_operation_mode(resolved_path, ops) if context["application"]&.debug

          begin
            execute_operation(resolved_path, ops)
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
            insert_after: arguments[:insert_after] || arguments["insert_after"],
            insert_before: arguments[:insert_before] || arguments["insert_before"],
            content: arguments[:content] || arguments["content"],
            insert_line: arguments[:insert_line] || arguments["insert_line"],
            replace_start: arguments[:replace_range_start] || arguments["replace_range_start"],
            replace_end: arguments[:replace_range_end] || arguments["replace_range_end"]
          }
        end

        def log_operation_mode(path, ops)
          app = context["application"]
          app.output.debug("[file_edit] file: #{path}")
          mode = determine_operation_mode(ops)
          app.output.debug("[file_edit] mode: #{mode}") if mode
        end

        def determine_operation_mode(ops)
          return "replace (replace_all: #{ops[:replace_all]})" if ops[:old_string]
          return "append" if ops[:append]
          return "prepend" if ops[:prepend]
          return "insert_after" if ops[:insert_after]
          return "insert_before" if ops[:insert_before]
          return "insert_line (#{ops[:insert_line]})" if ops[:insert_line]
          return "replace_range (#{ops[:replace_start]}-#{ops[:replace_end]})" if ops[:replace_start] && ops[:replace_end]

          nil
        end

        def execute_operation(path, ops)
          if ops[:old_string] && ops[:new_string]
            execute_replace(path, ops[:old_string], ops[:new_string], ops[:replace_all])
          elsif ops[:append]
            execute_append(path, ops[:append])
          elsif ops[:prepend]
            execute_prepend(path, ops[:prepend])
          elsif ops[:insert_after]
            execute_insert_after(path, ops[:insert_after], ops[:content])
          elsif ops[:insert_before]
            execute_insert_before(path, ops[:insert_before], ops[:content])
          elsif ops[:insert_line]
            execute_insert_line(path, ops[:insert_line], ops[:content])
          elsif ops[:replace_start] && ops[:replace_end]
            execute_replace_range(path, ops[:replace_start], ops[:replace_end], ops[:content])
          else
            {
              status: "error",
              error: "Must provide either: (old_string + new_string), append, prepend, " \
                     "(insert_after/insert_before + content), (insert_line + content), " \
                     "or (replace_range_start + replace_range_end + content)"
            }
          end
        end

        def resolve_path(file_path)
          # If relative path, make it relative to current directory
          if file_path.start_with?("/")
            File.expand_path(file_path)
          else
            File.expand_path(file_path, Dir.pwd)
          end
        end

        def validate_path(file_path)
          # Get the project root (current working directory)
          project_root = File.expand_path(Dir.pwd)

          # Ensure the file path is within the project directory
          unless file_path.start_with?(project_root)
            raise ArgumentError, "Access denied: File must be within project directory (#{project_root})"
          end

          # Prevent directory traversal attacks
          return unless file_path.include?("..")

          raise ArgumentError, "Access denied: Path cannot contain '..'"
        end

        def execute_replace(file_path, old_string, new_string, replace_all)
          raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

          # Read the file
          content = File.read(file_path)

          # Count occurrences
          occurrences = content.scan(old_string).length

          if occurrences.zero?
            return {
              status: "error",
              error: "old_string not found in file. Read the file first to verify the exact text to replace.",
              replacements: 0
            }
          end

          # Perform replacement
          new_content = if replace_all
                          content.gsub(old_string, new_string)
                        else
                          content.sub(old_string, new_string) # Only replace first occurrence
                        end

          # Write back
          File.write(file_path, new_content)

          {
            status: "success",
            file: file_path,
            replacements: replace_all ? occurrences : 1,
            total_occurrences: occurrences,
            replaced_all: replace_all
          }
        end

        def execute_append(file_path, content)
          raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

          # Append to file
          File.open(file_path, "a") do |file|
            file.write(content)
          end

          {
            status: "success",
            file: file_path,
            operation: "append",
            bytes_added: content.bytesize
          }
        end

        def execute_prepend(file_path, content)
          raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

          # Read current content
          existing_content = File.read(file_path)

          # Write new content + existing content
          File.write(file_path, content + existing_content)

          {
            status: "success",
            file: file_path,
            operation: "prepend",
            bytes_added: content.bytesize
          }
        end

        def execute_insert_after(file_path, pattern, content)
          raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

          raise ArgumentError, "content is required for insert_after operation" if content.nil? || content.empty?

          # Read file
          file_content = File.read(file_path)

          # Check if pattern exists
          unless file_content.include?(pattern)
            return {
              status: "error",
              error: "Pattern not found in file: '#{pattern}'"
            }
          end

          # Insert after first occurrence
          new_content = file_content.sub(pattern, pattern + content)

          # Write back
          File.write(file_path, new_content)

          {
            status: "success",
            file: file_path,
            operation: "insert_after",
            pattern: pattern,
            bytes_added: content.bytesize
          }
        end

        def execute_insert_before(file_path, pattern, content)
          raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

          raise ArgumentError, "content is required for insert_before operation" if content.nil? || content.empty?

          # Read file
          file_content = File.read(file_path)

          # Check if pattern exists
          unless file_content.include?(pattern)
            return {
              status: "error",
              error: "Pattern not found in file: '#{pattern}'"
            }
          end

          # Insert before first occurrence
          new_content = file_content.sub(pattern, content + pattern)

          # Write back
          File.write(file_path, new_content)

          {
            status: "success",
            file: file_path,
            operation: "insert_before",
            pattern: pattern,
            bytes_added: content.bytesize
          }
        end

        def execute_insert_line(file_path, line_number, content)
          raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

          raise ArgumentError, "content is required for insert_line operation" if content.nil? || content.empty?

          # Read file lines
          lines = File.readlines(file_path)
          total_lines = lines.length

          # Validate line number (1-indexed)
          if line_number < 1 || line_number > total_lines + 1
            max_line = total_lines + 1
            return {
              status: "error",
              error: "Invalid line number: #{line_number} (file has #{total_lines} lines, valid range: 1-#{max_line})"
            }
          end

          # Insert content at specified line (before the line number)
          # Ensure content ends with newline if it doesn't already
          content_to_insert = content.end_with?("\n") ? content : "#{content}\n"

          # Insert at index (line_number - 1) to insert before that line
          lines.insert(line_number - 1, content_to_insert)

          # Write back
          File.write(file_path, lines.join)

          {
            status: "success",
            file: file_path,
            operation: "insert_line",
            line_number: line_number,
            lines_added: content_to_insert.count("\n")
          }
        end

        def execute_replace_range(file_path, start_line, end_line, content)
          raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

          if content.nil?
            content = "" # Allow empty replacement (deletion)
          end

          # Read file lines
          lines = File.readlines(file_path)
          total_lines = lines.length

          # Validate line numbers (1-indexed, inclusive range)
          if start_line < 1 || start_line > total_lines
            return {
              status: "error",
              error: "Invalid start_line: #{start_line} (file has #{total_lines} lines)"
            }
          end

          if end_line < 1 || end_line > total_lines
            return {
              status: "error",
              error: "Invalid end_line: #{end_line} (file has #{total_lines} lines)"
            }
          end

          if start_line > end_line
            return {
              status: "error",
              error: "start_line (#{start_line}) must be <= end_line (#{end_line})"
            }
          end

          # Ensure content ends with newline if it's not empty
          content_to_insert = if content.empty?
                                ""
                              else
                                content.end_with?("\n") ? content : "#{content}\n"
                              end

          # Calculate how many lines we're removing
          lines_removed = end_line - start_line + 1

          # Replace the range (convert to 0-indexed)
          # Delete lines from start_line-1 to end_line-1 (inclusive)
          lines.slice!(start_line - 1, lines_removed)

          # Insert new content at start_line-1
          lines.insert(start_line - 1, content_to_insert) unless content_to_insert.empty?

          # Write back
          File.write(file_path, lines.join)

          {
            status: "success",
            file: file_path,
            operation: "replace_range",
            start_line: start_line,
            end_line: end_line,
            lines_removed: lines_removed,
            lines_added: content_to_insert.count("\n")
          }
        end
      end
    end
  end
end
