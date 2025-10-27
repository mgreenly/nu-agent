# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DirList
        PARAMETERS = {
          path: {
            type: "string",
            description: "Path to the directory to list (relative to project root or absolute within project). " \
                         "Defaults to current directory.",
            required: false
          },
          show_hidden: {
            type: "boolean",
            description: "Include hidden files (those starting with .). Default: false",
            required: false
          },
          details: {
            type: "boolean",
            description: "Include detailed information (size, type, mtime) for each entry like 'ls -l'. " \
                         "Default: false",
            required: false
          },
          sort_by: {
            type: "string",
            description: "How to sort results: 'name' (alphabetical), 'mtime' (modification time, newest first), " \
                         "'size' (largest first), or 'none'. Default: 'name'",
            required: false
          },
          limit: {
            type: "integer",
            description: "Maximum number of entries to return. Default: 1000",
            required: false
          }
        }.freeze

        def name
          "dir_list"
        end

        def description
          "PREFERRED tool for listing directory contents. " \
            "Returns structured list of files and directories with optional details. " \
            "Use this instead of execute_bash with ls commands. " \
            "Supports sorting by name/mtime/size, filtering hidden files, and detailed file information."
        end

        def parameters
          PARAMETERS
        end

        def execute(arguments:, **)
          args = parse_arguments(arguments)
          resolved_path = resolve_path(args[:dir_path])
          validate_path(resolved_path)

          begin
            error_response = validate_directory_path(resolved_path, args[:dir_path])
            return error_response if error_response

            entries = get_filtered_entries(resolved_path, args[:show_hidden])
            entry_list = build_entry_list(entries, resolved_path, args[:details])
            sorted_entries = sort_entries(entry_list, args[:sort_by], resolved_path, args[:details])
            limited_entries, truncated = apply_limit(sorted_entries, args[:limit], entries.length)

            build_success_response(args[:dir_path], limited_entries, entries.length, truncated)
          rescue StandardError => e
            {
              status: "error",
              error: "Failed to list directory: #{e.message}"
            }
          end
        end

        private

        def parse_arguments(arguments)
          {
            dir_path: get_arg(arguments, :path, "."),
            show_hidden: get_arg(arguments, :show_hidden, false),
            details: get_arg(arguments, :details, false),
            sort_by: get_arg(arguments, :sort_by, "name"),
            limit: get_arg(arguments, :limit, 1000)
          }
        end

        def get_arg(arguments, key, default)
          arguments[key] || arguments[key.to_s] || default
        end

        def validate_directory_path(resolved_path, dir_path)
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

          nil
        end

        def get_filtered_entries(resolved_path, show_hidden)
          entries = Dir.entries(resolved_path)

          # Filter out . and ..
          entries.reject! { |e| [".", ".."].include?(e) }

          # Filter hidden files if requested
          entries.reject! { |e| e.start_with?(".") } unless show_hidden

          entries
        end

        def build_entry_list(entries, resolved_path, details)
          entries.map do |entry|
            full_path = File.join(resolved_path, entry)

            if details
              build_detailed_entry(entry, full_path)
            else
              entry
            end
          end
        end

        def apply_limit(entries, limit, total_count)
          limited = entries.take(limit)
          truncated = total_count > limit
          [limited, truncated]
        end

        def build_success_response(dir_path, entries, total_count, truncated)
          {
            status: "success",
            path: dir_path,
            entries: entries,
            count: entries.length,
            total_entries: total_count,
            truncated: truncated
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

        def build_detailed_entry(name, full_path)
          stat = File.stat(full_path)

          type = if File.directory?(full_path)
                   "directory"
                 elsif File.symlink?(full_path)
                   "symlink"
                 elsif File.file?(full_path)
                   "file"
                 else
                   "other"
                 end

          {
            name: name,
            type: type,
            size: stat.size,
            modified_at: stat.mtime.iso8601
          }
        rescue StandardError
          # If we can't stat (e.g., broken symlink), return basic info
          {
            name: name,
            type: "unknown",
            size: 0,
            modified_at: nil
          }
        end

        def sort_entries(entries, sort_by, base_path, details_mode)
          case sort_by
          when "mtime"
            sort_by_mtime(entries, base_path, details_mode)
          when "size"
            sort_by_size(entries, base_path, details_mode)
          when "none"
            entries
          else
            # Default to name if invalid sort_by (or when sort_by == "name")
            sort_by_name(entries, details_mode)
          end
        end

        def sort_by_mtime(entries, base_path, details_mode)
          if details_mode
            entries.sort_by { |e| e[:modified_at] || "" }.reverse
          else
            entries.sort_by do |e|
              full_path = File.join(base_path, e)
              File.exist?(full_path) ? -File.mtime(full_path).to_i : 0
            end
          end
        end

        def sort_by_size(entries, base_path, details_mode)
          if details_mode
            entries.sort_by { |e| -e[:size] }
          else
            entries.sort_by do |e|
              full_path = File.join(base_path, e)
              File.exist?(full_path) ? -File.size(full_path) : 0
            end
          end
        end

        def sort_by_name(entries, details_mode)
          if details_mode
            entries.sort_by { |e| e[:name] }
          else
            entries.sort
          end
        end
      end
    end
  end
end
