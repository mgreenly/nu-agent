# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileWrite
        def name
          "file_write"
        end

        def description
          "PREFERRED tool for creating new files or completely overwriting existing files. " \
            "WARNING: Replaces entire file contents, use file_edit for targeted changes. " \
            "Automatically creates parent directories if needed."
        end

        def parameters
          {
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
          }
        end

        def execute(arguments:, history:, context:)
          file_path = arguments[:file] || arguments["file"]
          content = arguments[:content] || arguments["content"]

          if file_path.nil? || file_path.empty?
            return {
              status: "error",
              error: "file path is required"
            }
          end

          if content.nil?
            return {
              status: "error",
              error: "content is required"
            }
          end

          # Resolve and validate file path
          resolved_path = resolve_path(file_path)
          validate_path(resolved_path)

          begin
            # Create parent directory if it doesn't exist
            dir = File.dirname(resolved_path)
            FileUtils.mkdir_p(dir)

            # Write the file
            File.write(resolved_path, content)

            {
              status: "success",
              file: file_path,
              bytes_written: content.bytesize,
              lines_written: content.lines.length
            }
          rescue StandardError => e
            {
              status: "error",
              error: "Failed to write file: #{e.message}"
            }
          end
        end

        private

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
