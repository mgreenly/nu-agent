# frozen_string_literal: true

require_relative "edit_operation"

module Nu
  module Agent
    module Tools
      class FileEdit
        # Strategy for appending content to the end of a file
        class AppendOperation < EditOperation
          def execute(file_path, ops)
            raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

            content = ops[:content]

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
        end
      end
    end
  end
end
