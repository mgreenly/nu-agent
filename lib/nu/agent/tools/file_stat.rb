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

        def execute(arguments:, **)
          path = arguments[:path] || arguments["path"]

          return error_response("path is required") if path.nil? || path.empty?

          resolved_path = resolve_path(path)
          validate_path(resolved_path)

          begin
            return error_response("Path not found: #{path}") unless File.exist?(resolved_path)

            stat = File.stat(resolved_path)
            file_type = determine_file_type(resolved_path)

            result = build_base_result(path, resolved_path, stat, file_type)
            add_extra_attributes(result, resolved_path, file_type, stat.size)

            result
          rescue StandardError => e
            error_response("Failed to get file stats: #{e.message}")
          end
        end

        private

        def error_response(message)
          { status: "error", error: message }
        end

        def determine_file_type(resolved_path)
          return "directory" if File.directory?(resolved_path)
          return "file" if File.file?(resolved_path)
          return "symlink" if File.symlink?(resolved_path)

          "other"
        end

        def build_base_result(path, resolved_path, stat, file_type)
          {
            status: "success",
            path: path,
            type: file_type,
            size_bytes: stat.size,
            permissions: format("%o", stat.mode & 0o777),
            readable: File.readable?(resolved_path),
            writable: File.writable?(resolved_path),
            executable: File.executable?(resolved_path),
            modified_at: stat.mtime.iso8601,
            accessed_at: stat.atime.iso8601,
            created_at: stat.ctime.iso8601
          }
        end

        def add_extra_attributes(result, resolved_path, file_type, size)
          result[:size_human] = human_readable_size(size)

          result[:entries] = Dir.entries(resolved_path).length - 2 if file_type == "directory"

          result[:symlink_target] = File.readlink(resolved_path) if File.symlink?(resolved_path)
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
            raise ArgumentError, "Access denied: Path must be within project directory (#{project_root})"
          end

          return unless file_path.include?("..")

          raise ArgumentError, "Access denied: Path cannot contain '..'"
        end

        def human_readable_size(bytes)
          units = %w[B KB MB GB TB]
          return "0 B" if bytes.zero?

          exp = (Math.log(bytes) / Math.log(1024)).to_i
          exp = [exp, units.length - 1].min

          size = bytes / (1024.0**exp)
          format("%<size>.2f %<unit>s", size: size, unit: units[exp])
        end
      end
    end
  end
end
