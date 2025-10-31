# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileTree
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
            description: "Include hidden files (those in paths starting with .). Default: false",
            required: false
          },
          limit: {
            type: "integer",
            description: "Maximum number of files to return. Default: 1000",
            required: false
          }
        }.freeze

        def name
          "file_tree"
        end

        def description
          "PREFERRED tool for discovering file structure. Returns flat list of all files below a path. " \
            "Use this instead of execute_bash with find commands for file discovery. " \
            "Results are limited to prevent overwhelming output in large projects."
        end

        def parameters
          PARAMETERS
        end

        def operation_type
          :read
        end

        def scope
          :confined
        end

        def execute(arguments:, **)
          args = parse_arguments(arguments)

          begin
            resolved_path = resolve_path(args[:dir_path])
            validate_path(resolved_path)

            error = validate_directory(resolved_path, args[:dir_path])
            return error if error

            all_files = execute_find_and_parse(resolved_path, args)
            files = all_files.take(args[:limit])

            build_success_response(args[:dir_path], files, all_files.length, args[:limit])
          rescue StandardError => e
            error_response("Failed to list files: #{e.message}")
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
                .sort
        end

        def build_success_response(dir_path, files, total_files, limit)
          {
            status: "success",
            path: dir_path,
            files: files,
            count: files.length,
            total_files: total_files,
            truncated: total_files > limit
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
