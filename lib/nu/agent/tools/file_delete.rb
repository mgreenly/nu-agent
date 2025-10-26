# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileDelete
        def name
          "file_delete"
        end

        def description
          "PREFERRED tool for deleting files. WARNING: Cannot be undone, file is permanently removed. " \
          "Only use when you're certain the file should be deleted."
        end

        def parameters
          {
            file: {
              type: "string",
              description: "Path to the file to delete (relative to project root or absolute within project)",
              required: true
            }
          }
        end

        def execute(arguments:, history:, context:)
          file_path = arguments[:file] || arguments["file"]

          if file_path.nil? || file_path.empty?
            return {
              status: "error",
              error: "file path is required"
            }
          end

          # Resolve and validate file path
          resolved_path = resolve_path(file_path)
          validate_path(resolved_path)

          # Debug output
          if application = context['application']

            buffer = Nu::Agent::OutputBuffer.new
            buffer.debug("[file_delete] file: #{resolved_path}")

            application.output.flush_buffer(buffer)
          end

          begin
            unless File.exist?(resolved_path)
              return {
                status: "error",
                error: "File not found: #{file_path}"
              }
            end

            unless File.file?(resolved_path)
              return {
                status: "error",
                error: "Not a file (may be a directory): #{file_path}"
              }
            end

            # Delete the file
            File.delete(resolved_path)

            {
              status: "success",
              file: file_path,
              message: "File deleted successfully"
            }
          rescue => e
            {
              status: "error",
              error: "Failed to delete file: #{e.message}"
            }
          end
        end

        private

        def resolve_path(file_path)
          if file_path.start_with?('/')
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

          if file_path.include?('..')
            raise ArgumentError, "Access denied: Path cannot contain '..'"
          end
        end
      end
    end
  end
end
