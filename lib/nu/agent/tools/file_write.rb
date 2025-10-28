# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileWrite
        PARAMETERS = {
          file: {
            type: "string",
            description: "Path to the file (relative to project root or absolute within project)",
            required: true
          },
          content: {
            type: "string",
            description: "Complete content to write to the file",
            required: true
          }
        }.freeze

        def name
          "file_write"
        end

        def description
          "PREFERRED tool for creating new files or completely overwriting existing files. " \
            "WARNING: Replaces entire file contents, use file_edit for targeted changes. " \
            "Automatically creates parent directories if needed."
        end

        def parameters
          PARAMETERS
        end

        def execute(arguments:, **)
          file_path = extract_argument(arguments, :file)
          content = extract_argument(arguments, :content)

          return validation_error("file path is required") if file_path.nil? || file_path.empty?
          return validation_error("content is required") if content.nil?

          resolved_path = resolve_path(file_path)
          validate_path(resolved_path)

          write_file_to_disk(file_path, content, resolved_path)
        end

        private

        def extract_argument(arguments, key)
          arguments[key] || arguments[key.to_s]
        end

        def validation_error(message)
          { status: "error", error: message }
        end

        def write_file_to_disk(file_path, content, resolved_path)
          FileUtils.mkdir_p(File.dirname(resolved_path))
          File.write(resolved_path, content)

          {
            status: "success",
            file: file_path,
            bytes_written: content.bytesize,
            lines_written: content.lines.length
          }
        rescue StandardError => e
          { status: "error", error: "Failed to write file: #{e.message}" }
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
