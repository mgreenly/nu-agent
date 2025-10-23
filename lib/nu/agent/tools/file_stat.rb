# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileStat
        def name
          "file_stat"
        end

        def description
          "PREFERRED tool for getting file or directory metadata and statistics. " \
          "Returns detailed information including size, modification time, permissions, and file type. " \
          "Use this instead of execute_bash with stat/ls -l commands."
        end

        def parameters
          {
            path: {
              type: "string",
              description: "Path to the file or directory (relative to project root or absolute within project)",
              required: true
            }
          }
        end

        def execute(arguments:, history:, context:)
          path = arguments[:path] || arguments["path"]

          if path.nil? || path.empty?
            return {
              status: "error",
              error: "path is required"
            }
          end

          # Resolve and validate path
          resolved_path = resolve_path(path)
          validate_path(resolved_path)

          # Debug output
          if application = context['application']
            application.output.debug("[file_stat] path: #{resolved_path}")
          end

          begin
            unless File.exist?(resolved_path)
              return {
                status: "error",
                error: "Path not found: #{path}"
              }
            end

            stat = File.stat(resolved_path)

            # Determine file type
            file_type = if File.directory?(resolved_path)
              "directory"
            elsif File.file?(resolved_path)
              "file"
            elsif File.symlink?(resolved_path)
              "symlink"
            else
              "other"
            end

            # Format permissions as octal string (e.g., "0755")
            permissions = sprintf("%o", stat.mode & 0777)

            # Build result
            result = {
              status: "success",
              path: path,
              type: file_type,
              size_bytes: stat.size,
              permissions: permissions,
              readable: File.readable?(resolved_path),
              writable: File.writable?(resolved_path),
              executable: File.executable?(resolved_path),
              modified_at: stat.mtime.iso8601,
              accessed_at: stat.atime.iso8601,
              created_at: stat.ctime.iso8601
            }

            # Add human-readable size
            result[:size_human] = human_readable_size(stat.size)

            # For directories, include entry count
            if file_type == "directory"
              entry_count = Dir.entries(resolved_path).length - 2 # Exclude . and ..
              result[:entries] = entry_count
            end

            # For symlinks, include target
            if File.symlink?(resolved_path)
              result[:symlink_target] = File.readlink(resolved_path)
            end

            result
          rescue => e
            {
              status: "error",
              error: "Failed to get file stats: #{e.message}"
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
            raise ArgumentError, "Access denied: Path must be within project directory (#{project_root})"
          end

          if file_path.include?('..')
            raise ArgumentError, "Access denied: Path cannot contain '..'"
          end
        end

        def human_readable_size(bytes)
          units = ['B', 'KB', 'MB', 'GB', 'TB']
          return "0 B" if bytes == 0

          exp = (Math.log(bytes) / Math.log(1024)).to_i
          exp = [exp, units.length - 1].min

          size = bytes / (1024.0 ** exp)
          "%.2f %s" % [size, units[exp]]
        end
      end
    end
  end
end
