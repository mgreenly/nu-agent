# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileCopy
        PARAMETERS = {
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
        }.freeze

        def name
          "file_copy"
        end

        def description
          "PREFERRED tool for copying files. Creates duplicate at destination, original remains unchanged. " \
            "Automatically creates destination parent directories if needed. " \
            "WARNING: Overwrites destination if it already exists."
        end

        def parameters
          PARAMETERS
        end

        def execute(arguments:, **)
          source_path = extract_argument(arguments, :source)
          dest_path = extract_argument(arguments, :destination)

          return validation_error("source path is required") if source_path.nil? || source_path.empty?
          return validation_error("destination path is required") if dest_path.nil? || dest_path.empty?

          resolved_source = resolve_path(source_path)
          resolved_dest = resolve_path(dest_path)

          validate_path(resolved_source)
          validate_path(resolved_dest)

          error = validate_source_file(resolved_source, source_path)
          return error if error

          perform_copy(source_path, dest_path, resolved_source, resolved_dest)
        end

        private

        def extract_argument(arguments, key)
          arguments[key] || arguments[key.to_s]
        end

        def validation_error(message)
          { status: "error", error: message }
        end

        def validate_source_file(resolved_source, source_path)
          return validation_error("Source file not found: #{source_path}") unless File.exist?(resolved_source)
          return validation_error("Source is not a file: #{source_path}") unless File.file?(resolved_source)

          nil
        end

        def perform_copy(source_path, dest_path, resolved_source, resolved_dest)
          FileUtils.mkdir_p(File.dirname(resolved_dest))
          FileUtils.cp(resolved_source, resolved_dest)

          {
            status: "success",
            source: source_path,
            destination: dest_path,
            bytes_copied: File.size(resolved_dest),
            message: "File copied successfully"
          }
        rescue StandardError => e
          validation_error("Failed to copy file: #{e.message}")
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
