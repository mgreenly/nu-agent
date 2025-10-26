# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DirCreate
        def name
          "dir_create"
        end

        def description
          "PREFERRED tool for creating directories. " \
            "Automatically creates parent directories if needed (like mkdir -p). " \
            "Safe to call if directory already exists (no error). " \
            "Use this to organize files into new directory structures."
        end

        def parameters
          {
            path: {
              type: "string",
              description: "Path to the directory to create (relative to project root or absolute within project)",
              required: true
            }
          }
        end

        def execute(arguments:, history:, context:)
          dir_path = arguments[:path] || arguments["path"]

          if dir_path.nil? || dir_path.empty?
            return {
              status: "error",
              error: "path is required"
            }
          end

          # Resolve and validate path
          resolved_path = resolve_path(dir_path)
          validate_path(resolved_path)

          # Debug output
          context["application"]

          begin
            # Check if it already exists
            if Dir.exist?(resolved_path)
              return {
                status: "success",
                path: dir_path,
                message: "Directory already exists",
                created: false
              }
            end

            # Create directory and parents if needed
            FileUtils.mkdir_p(resolved_path)

            {
              status: "success",
              path: dir_path,
              message: "Directory created successfully",
              created: true
            }
          rescue StandardError => e
            {
              status: "error",
              error: "Failed to create directory: #{e.message}"
            }
          end
        end

        private

        def resolve_path(dir_path)
          if dir_path.start_with?("/")
            File.expand_path(dir_path)
          else
            File.expand_path(dir_path, Dir.pwd)
          end
        end

        def validate_path(dir_path)
          project_root = File.expand_path(Dir.pwd)

          unless dir_path.start_with?(project_root)
            raise ArgumentError, "Access denied: Directory must be within project directory (#{project_root})"
          end

          return unless dir_path.include?("..")

          raise ArgumentError, "Access denied: Path cannot contain '..'"
        end
      end
    end
  end
end
