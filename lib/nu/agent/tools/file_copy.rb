# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileCopy
        def name
          "file_copy"
        end

        def description
          "PREFERRED tool for copying files. Creates duplicate at destination, original remains unchanged. " \
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

        def execute(arguments:, **)
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
            FileUtils.mkdir_p(dest_dir)

            # Copy the file
            FileUtils.cp(resolved_source, resolved_dest)

            {
              status: "success",
              source: source_path,
              destination: dest_path,
              bytes_copied: File.size(resolved_dest),
              message: "File copied successfully"
            }
          rescue StandardError => e
            {
              status: "error",
              error: "Failed to copy file: #{e.message}"
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
