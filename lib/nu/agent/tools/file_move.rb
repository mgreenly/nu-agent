# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileMove
        def name
          "file_move"
        end

        def description
          "PREFERRED tool for moving or renaming files. Can move between directories or rename in place. " \
          "Automatically creates destination parent directories if needed. " \
          "WARNING: Overwrites destination if it already exists."
        end

        def parameters
          {
            source: {
              type: "string",
              description: "Path to the source file (relative to project root or absolute within project)",
              required: true
            },
            destination: {
              type: "string",
              description: "Path to the destination (relative to project root or absolute within project)",
              required: true
            }
          }
        end

        def execute(arguments:, history:, context:)
          source_path = arguments[:source] || arguments["source"]
          dest_path = arguments[:destination] || arguments["destination"]

          if source_path.nil? || source_path.empty?
            return {
              status: "error",
              error: "source path is required"
            }
          end

          if dest_path.nil? || dest_path.empty?
            return {
              status: "error",
              error: "destination path is required"
            }
          end

          # Resolve and validate paths
          resolved_source = resolve_path(source_path)
          resolved_dest = resolve_path(dest_path)

          validate_path(resolved_source)
          validate_path(resolved_dest)

          # Debug output
          if application = context['application']

            buffer = Nu::Agent::OutputBuffer.new
            buffer.debug("[file_move] source: #{resolved_source}")

            buffer.debug("[file_move] destination: #{resolved_dest}")

            application.output.flush_buffer(buffer)
          end

          begin
            unless File.exist?(resolved_source)
              return {
                status: "error",
                error: "Source file not found: #{source_path}"
              }
            end

            unless File.file?(resolved_source)
              return {
                status: "error",
                error: "Source is not a file: #{source_path}"
              }
            end

            # Create destination directory if needed
            dest_dir = File.dirname(resolved_dest)
            FileUtils.mkdir_p(dest_dir) unless Dir.exist?(dest_dir)

            # Move the file
            FileUtils.mv(resolved_source, resolved_dest)

            {
              status: "success",
              source: source_path,
              destination: dest_path,
              message: "File moved successfully"
            }
          rescue => e
            {
              status: "error",
              error: "Failed to move file: #{e.message}"
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
