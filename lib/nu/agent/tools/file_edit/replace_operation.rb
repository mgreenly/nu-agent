# frozen_string_literal: true

require_relative "edit_operation"

module Nu
  module Agent
    module Tools
      class FileEdit
        # Strategy for replacing text in a file
        # Supports replacing first occurrence or all occurrences
        class ReplaceOperation < EditOperation
          def execute(file_path, ops)
            raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

            old_string = ops[:old_string]
            new_string = ops[:new_string]
            replace_all = ops[:replace_all]

            content = File.read(file_path)
            occurrences = content.scan(old_string).length

            return error_not_found if occurrences.zero?

            new_content = perform_replacement(content, old_string, new_string, replace_all)
            File.write(file_path, new_content)

            success_result(file_path, occurrences, replace_all)
          end

          private

          def error_not_found
            {
              status: "error",
              error: "old_string not found in file. Read the file first to verify the exact text to replace.",
              replacements: 0
            }
          end

          def perform_replacement(content, old_string, new_string, replace_all)
            if replace_all
              content.gsub(old_string, new_string)
            else
              content.sub(old_string, new_string) # Only replace first occurrence
            end
          end

          def success_result(file_path, occurrences, replace_all)
            {
              status: "success",
              file: file_path,
              replacements: replace_all ? occurrences : 1,
              total_occurrences: occurrences,
              replaced_all: replace_all
            }
          end
        end
      end
    end
  end
end
