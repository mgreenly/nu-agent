# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DirDelete
        def name
          "dir_delete"
        end

        def description
          "PREFERRED tool for deleting directories. REQUIRES TWO-STEP CONFIRMATION: First call shows preview, second call with confirm_delete=true deletes. " \
            "WARNING: Cannot be undone, all files and subdirectories are permanently removed. " \
            "Use with extreme caution."
        end

        def parameters
          {
            path: {
              type: "string",
              description: "Path to the directory to delete (relative to project root or absolute within project)",
              required: true
            },
            confirm_delete: {
              type: "boolean",
              description: "Set to true to confirm deletion after reviewing what will be deleted. Required for actual deletion.",
              required: false
            }
          }
        end

        def execute(arguments:, history:, context:)
          dir_path = arguments[:path] || arguments["path"]
          confirm = arguments[:confirm_delete] || arguments["confirm_delete"] || false

          if dir_path.nil? || dir_path.empty?
            return {
              status: "error",
              error: "path is required"
            }
          end

          # Resolve and validate path
          resolved_path = resolve_path(dir_path)
          validate_path(resolved_path)

          begin
            unless Dir.exist?(resolved_path)
              return {
                status: "error",
                error: "Directory not found: #{dir_path}"
              }
            end

            # Count what would be deleted
            file_count = count_files(resolved_path)
            dir_count = count_directories(resolved_path)
            total_size = calculate_size(resolved_path)

            # If not confirmed, return preview
            unless confirm
              return {
                status: "confirmation_required",
                path: dir_path,
                warning: "DESTRUCTIVE OPERATION - This will permanently delete:",
                files_to_delete: file_count,
                directories_to_delete: dir_count,
                total_size_bytes: total_size,
                message: "To proceed with deletion, call this tool again with confirm_delete: true",
                confirmed: false
              }
            end

            # Confirmed - proceed with deletion
            FileUtils.rm_rf(resolved_path)

            {
              status: "success",
              path: dir_path,
              message: "Directory deleted successfully",
              files_deleted: file_count,
              directories_deleted: dir_count,
              confirmed: true
            }
          rescue StandardError => e
            {
              status: "error",
              error: "Failed to delete directory: #{e.message}"
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

          raise ArgumentError, "Access denied: Path cannot contain '..'" if dir_path.include?("..")

          # Extra safety: prevent deleting project root
          return unless dir_path == project_root

          raise ArgumentError, "Access denied: Cannot delete project root directory"
        end

        def count_files(dir_path)
          count = 0
          Dir.glob(File.join(dir_path, "**", "*")).each do |path|
            count += 1 if File.file?(path)
          end
          count
        end

        def count_directories(dir_path)
          count = 0
          Dir.glob(File.join(dir_path, "**", "*")).each do |path|
            count += 1 if File.directory?(path)
          end
          count
        end

        def calculate_size(dir_path)
          total = 0
          Dir.glob(File.join(dir_path, "**", "*")).each do |path|
            total += File.size(path) if File.file?(path)
          end
          total
        end
      end
    end
  end
end
