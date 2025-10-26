# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DirTree
        def name
          "dir_tree"
        end

        def description
          "PREFERRED tool for discovering directory structure. Returns flat list of all subdirectories below a path. " \
            "Use this instead of execute_bash with find commands for directory discovery. " \
            "Results are limited to prevent overwhelming output in large projects."
        end

        def parameters
          {
            path: {
              type: "string",
              description: "Directory to start from (relative to project root or absolute within project). Defaults to current directory.",
              required: false
            },
            max_depth: {
              type: "integer",
              description: "Maximum depth to traverse. If not specified, traverses all levels.",
              required: false
            },
            show_hidden: {
              type: "boolean",
              description: "Include hidden directories (those starting with .). Default: false",
              required: false
            },
            limit: {
              type: "integer",
              description: "Maximum number of directories to return. Default: 1000",
              required: false
            }
          }
        end

        def execute(arguments:, **)
          dir_path = arguments[:path] || arguments["path"] || "."
          max_depth = arguments[:max_depth] || arguments["max_depth"]
          show_hidden = arguments[:show_hidden] || arguments["show_hidden"] || false
          limit = arguments[:limit] || arguments["limit"] || 1000

          # Resolve and validate path
          resolved_path = resolve_path(dir_path)
          validate_path(resolved_path)

          begin
            unless File.exist?(resolved_path)
              return {
                status: "error",
                error: "Directory not found: #{dir_path}"
              }
            end

            unless File.directory?(resolved_path)
              return {
                status: "error",
                error: "Not a directory: #{dir_path}"
              }
            end

            # Build find command
            cmd = build_find_command(resolved_path, max_depth, show_hidden)

            # Execute find
            stdout, stderr, status = Open3.capture3(*cmd)

            unless status.success?
              return {
                status: "error",
                error: "Failed to list directories: #{stderr}"
              }
            end

            # Parse output - make paths relative to starting directory
            all_directories = stdout.split("\n")
                                    .map(&:strip)
                                    .reject(&:empty?)
                                    .map { |path| make_relative(path, resolved_path) }
                                    .reject { |path| path == "." } # Exclude the starting directory itself
                                    .sort

            total_directories = all_directories.length
            directories = all_directories.take(limit)

            {
              status: "success",
              path: dir_path,
              directories: directories,
              count: directories.length,
              total_directories: total_directories,
              truncated: total_directories > limit
            }
          rescue StandardError => e
            {
              status: "error",
              error: "Failed to list directories: #{e.message}"
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

        def build_find_command(path, max_depth, show_hidden)
          cmd = ["find", path, "-type", "d"]

          # Add max depth if specified
          cmd += ["-maxdepth", max_depth.to_s] if max_depth

          # Exclude hidden directories unless show_hidden is true
          cmd += ["-not", "-path", "*/.*"] unless show_hidden

          cmd
        end

        def make_relative(absolute_path, base_path)
          # Remove base_path prefix to make it relative
          if absolute_path.start_with?(base_path)
            relative = absolute_path[base_path.length..]
            relative = relative[1..] if relative.start_with?("/") # Remove leading slash
            relative.empty? ? "." : relative
          else
            absolute_path
          end
        end
      end
    end
  end
end
