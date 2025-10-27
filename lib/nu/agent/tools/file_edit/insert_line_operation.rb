# frozen_string_literal: true

require_relative "edit_operation"

module Nu
  module Agent
    module Tools
      class FileEdit
        # Strategy for inserting content at a specific line number
        class InsertLineOperation < EditOperation
          def execute(file_path, ops)
            raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

            line_number = ops[:line_number]
            content = ops[:content]

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

            # Ensure content ends with newline
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
        end
      end
    end
  end
end
