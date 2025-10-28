# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileDelete
        PARAMETERS = {
          file: {
            type: "string",
            description: "Path to the file to delete (relative to project root or absolute within project)",
            required: true
          }
        }.freeze

        def name
          "file_delete"
        end

        def description
          "PREFERRED tool for deleting files. WARNING: Cannot be undone, file is permanently removed. " \
            "Only use when you're certain the file should be deleted."
        end

        def parameters
          PARAMETERS
        end

        def execute(arguments:, **)
          file_path = extract_argument(arguments, :file)

          return validation_error("file path is required") if file_path.nil? || file_path.empty?

          resolved_path = resolve_path(file_path)
          validate_path(resolved_path)

          error = validate_file_exists(resolved_path, file_path)
          return error if error

          perform_delete(file_path, resolved_path)
        end

        private

        def extract_argument(arguments, key)
          arguments[key] || arguments[key.to_s]
        end

        def validation_error(message)
          { status: "error", error: message }
        end

        def validate_file_exists(resolved_path, file_path)
          return validation_error("File not found: #{file_path}") unless File.exist?(resolved_path)
          return validation_error("Not a file (may be a directory): #{file_path}") unless File.file?(resolved_path)

          nil
        end

        def perform_delete(file_path, resolved_path)
          File.delete(resolved_path)

          {
            status: "success",
            file: file_path,
            message: "File deleted successfully"
          }
        rescue StandardError => e
          validation_error("Failed to delete file: #{e.message}")
        end

        def resolve_path(file_path)
          if file_path.start_with?("/")
            File.expand_path(file_path)
          else
            File.expand_path(file_path, Dir.pwd)
          end
        end

        def validate_path(file_path)
          project_root = File.expand_path(Dir.pwd)

          unless file_path.start_with?(project_root)
            raise ArgumentError, "Access denied: File must be within project directory (#{project_root})"
          end

          return unless file_path.include?("..")

          raise ArgumentError, "Access denied: Path cannot contain '..'"
        end
      end
    end
  end
end
