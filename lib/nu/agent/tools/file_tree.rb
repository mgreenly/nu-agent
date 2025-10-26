# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileTree
        def name
          "file_tree"
        end

        def description
          "PREFERRED tool for discovering file structure. Returns flat list of all files below a path. " \
            "Use this instead of execute_bash with find commands for file discovery. " \
            "Results are limited to prevent overwhelming output in large projects."
        end

        def parameters
          {
            path: {
              type: "string",
              description: "Directory to start from (relative to project root or absolute within project). " \
                           "Defaults to current directory.",
              required: false
            },
            max_depth: {
              type: "integer",
              description: "Maximum depth to traverse. If not specified, traverses all levels.",
              required: false
            },
            show_hidden: {
              type: "boolean",
              description: "Include hidden files (those in paths starting with .). Default: false",
              required: false
            },
            limit: {
              type: "integer",
              description: "Maximum number of files to return. Default: 1000",
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
                error: "Failed to list files: #{stderr}"
              }
            end

            # Parse output - make paths relative to starting directory
            all_files = stdout.split("\n")
                              .map(&:strip)
                              .reject(&:empty?)
                              .map { |path| make_relative(path, resolved_path) }
                              .sort

            total_files = all_files.length
            files = all_files.take(limit)

            {
              status: "success",
              path: dir_path,
              files: files,
              count: files.length,
              total_files: total_files,
              truncated: total_files > limit
            }
          rescue StandardError => e
            {
              status: "error",
              error: "Failed to list files: #{e.message}"
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
          cmd = ["find", path, "-type", "f"]

          # Add max depth if specified
          cmd += ["-maxdepth", max_depth.to_s] if max_depth

          # Exclude hidden files unless show_hidden is true
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
