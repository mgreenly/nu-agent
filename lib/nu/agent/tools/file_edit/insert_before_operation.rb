# frozen_string_literal: true

require_relative "edit_operation"

module Nu
  module Agent
    module Tools
      class FileEdit
        # Strategy for inserting content before a pattern match
        class InsertBeforeOperation < EditOperation
          def execute(file_path, ops)
            raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

            pattern = ops[:pattern]
            content = ops[:content]

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
        end
      end
    end
  end
end
