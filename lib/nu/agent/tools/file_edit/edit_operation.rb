# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileEdit
        # Base class for all file edit operations
        # Implements common functionality like path validation and resolution
        class EditOperation
          # Execute the edit operation
          # @param file_path [String] Path to the file
          # @param ops [Hash] Operation parameters
          # @return [Hash] Result with status and details
          def execute(file_path, ops)
            raise NotImplementedError, "Subclasses must implement #execute"
          end

          # Resolve file path (absolute or relative to project root)
          def resolve_path(file_path)
            if file_path.start_with?("/")
              File.expand_path(file_path)
            else
              File.expand_path(file_path, Dir.pwd)
            end
          end

          # Validate that path is within project directory and safe
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
end
