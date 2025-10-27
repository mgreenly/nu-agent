# frozen_string_literal: true

require_relative "edit_operation"

module Nu
  module Agent
    module Tools
      class FileEdit
        # Strategy for prepending content to the beginning of a file
        class PrependOperation < EditOperation
          def execute(file_path, ops)
            raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

            content = ops[:content]

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
        end
      end
    end
  end
end
