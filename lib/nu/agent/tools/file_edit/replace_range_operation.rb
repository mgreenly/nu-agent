# frozen_string_literal: true

require_relative "edit_operation"

module Nu
  module Agent
    module Tools
      class FileEdit
        # Strategy for replacing a range of lines with new content
        class ReplaceRangeOperation < EditOperation
          def execute(file_path, ops)
            raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

            start_line = ops[:start_line]
            end_line = ops[:end_line]
            content = ops[:content] || ""

            # Read file lines
            lines = File.readlines(file_path)
            total_lines = lines.length

            # Validate line numbers
            error = validate_line_range(start_line, end_line, total_lines)
            return error if error

            # Prepare content
            content_to_insert = prepare_content(content)

            # Calculate lines removed
            lines_removed = end_line - start_line + 1

            # Replace the range
            lines.slice!(start_line - 1, lines_removed)
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

          private

          def validate_line_range(start_line, end_line, total_lines)
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

            return unless start_line > end_line

            {
              status: "error",
              error: "start_line (#{start_line}) must be <= end_line (#{end_line})"
            }
          end

          def prepare_content(content)
            return "" if content.empty?

            content.end_with?("\n") ? content : "#{content}\n"
          end
        end
      end
    end
  end
end
