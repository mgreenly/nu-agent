# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DirTree
        PARAMETERS = {
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
            description: "Include hidden directories (those starting with .). Default: false",
            required: false
          },
          limit: {
            type: "integer",
            description: "Maximum number of directories to return. Default: 1000",
            required: false
          }
        }.freeze

        def name
          "dir_tree"
        end

        def description
          "PREFERRED tool for discovering directory structure. Returns flat list of all subdirectories below a path. " \
            "Use this instead of execute_bash with find commands for directory discovery. " \
            "Results are limited to prevent overwhelming output in large projects."
        end

        def parameters
          PARAMETERS
        end

        def execute(arguments:, **)
          args = parse_arguments(arguments)

          begin
            resolved_path = resolve_path(args[:dir_path])
            validate_path(resolved_path)

            error = validate_directory(resolved_path, args[:dir_path])
            return error if error

            all_directories = execute_find_and_parse(resolved_path, args)
            directories = all_directories.take(args[:limit])

            build_success_response(args[:dir_path], directories, all_directories.length, args[:limit])
          rescue StandardError => e
            error_response("Failed to list directories: #{e.message}")
          end
        end

        private

        def parse_arguments(arguments)
          {
            dir_path: arguments[:path] || arguments["path"] || ".",
            max_depth: arguments[:max_depth] || arguments["max_depth"],
            show_hidden: arguments[:show_hidden] || arguments["show_hidden"] || false,
            limit: arguments[:limit] || arguments["limit"] || 1000
          }
        end

        def error_response(message)
          { status: "error", error: message }
        end

        def validate_directory(resolved_path, dir_path)
          return error_response("Directory not found: #{dir_path}") unless File.exist?(resolved_path)
          return error_response("Not a directory: #{dir_path}") unless File.directory?(resolved_path)

          nil
        end

        def execute_find_and_parse(resolved_path, args)
          cmd = build_find_command(resolved_path, args[:max_depth], args[:show_hidden])
          stdout, stderr, status = Open3.capture3(*cmd)

          raise StandardError, "find command failed: #{stderr}" unless status.success?

          parse_find_output(stdout, resolved_path)
        end

        def parse_find_output(stdout, resolved_path)
          stdout.split("\n")
                .map(&:strip)
                .reject(&:empty?)
                .map { |path| make_relative(path, resolved_path) }
                .reject { |path| path == "." }
                .sort
        end

        def build_success_response(dir_path, directories, total_directories, limit)
          {
            status: "success",
            path: dir_path,
            directories: directories,
            count: directories.length,
            total_directories: total_directories,
            truncated: total_directories > limit
          }
        end

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
