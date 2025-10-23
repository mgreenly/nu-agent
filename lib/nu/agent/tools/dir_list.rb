# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DirList
        def name
          "dir_list"
        end

        def description
          "PREFERRED tool for listing directory contents. Returns structured list of files and directories with optional details. " \
          "Use this instead of execute_bash with ls commands. " \
          "Supports sorting by name/mtime/size, filtering hidden files, and detailed file information."
        end

        def parameters
          {
            path: {
              type: "string",
              description: "Path to the directory to list (relative to project root or absolute within project). Defaults to current directory.",
              required: false
            },
            show_hidden: {
              type: "boolean",
              description: "Include hidden files (those starting with .). Default: false",
              required: false
            },
            details: {
              type: "boolean",
              description: "Include detailed information (size, type, mtime) for each entry like 'ls -l'. Default: false",
              required: false
            },
            sort_by: {
              type: "string",
              description: "How to sort results: 'name' (alphabetical), 'mtime' (modification time, newest first), 'size' (largest first), or 'none'. Default: 'name'",
              required: false
            },
            limit: {
              type: "integer",
              description: "Maximum number of entries to return. Default: 1000",
              required: false
            }
          }
        end

        def execute(arguments:, history:, context:)
          dir_path = arguments[:path] || arguments["path"] || "."
          show_hidden = arguments[:show_hidden] || arguments["show_hidden"] || false
          details = arguments[:details] || arguments["details"] || false
          sort_by = arguments[:sort_by] || arguments["sort_by"] || "name"
          limit = arguments[:limit] || arguments["limit"] || 1000

          # Resolve and validate path
          resolved_path = resolve_path(dir_path)
          validate_path(resolved_path)

          # Debug output
          if application = context['application']
            application.output.debug("[dir_list] path: #{resolved_path}")
            application.output.debug("[dir_list] show_hidden: #{show_hidden}, details: #{details}, sort_by: #{sort_by}")
          end

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

            # Get directory entries
            entries = Dir.entries(resolved_path)

            # Filter out . and ..
            entries.reject! { |e| e == "." || e == ".." }

            # Filter hidden files if requested
            unless show_hidden
              entries.reject! { |e| e.start_with?(".") }
            end

            # Build entry list with optional details
            entry_list = entries.map do |entry|
              full_path = File.join(resolved_path, entry)

              if details
                build_detailed_entry(entry, full_path)
              else
                entry
              end
            end

            # Sort entries
            sorted_entries = sort_entries(entry_list, sort_by, resolved_path, details)

            # Limit results
            limited_entries = sorted_entries.take(limit)

            {
              status: "success",
              path: dir_path,
              entries: limited_entries,
              count: limited_entries.length,
              total_entries: entries.length,
              truncated: entries.length > limit
            }
          rescue => e
            {
              status: "error",
              error: "Failed to list directory: #{e.message}"
            }
          end
        end

        private

        def resolve_path(dir_path)
          if dir_path.start_with?('/')
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

          if dir_path.include?('..')
            raise ArgumentError, "Access denied: Path cannot contain '..'"
          end
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
        rescue
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
          when "name"
            if details_mode
              entries.sort_by { |e| e[:name] }
            else
              entries.sort
            end
          when "mtime"
            if details_mode
              entries.sort_by { |e| e[:modified_at] || "" }.reverse
            else
              entries.sort_by do |e|
                full_path = File.join(base_path, e)
                File.exist?(full_path) ? -File.mtime(full_path).to_i : 0
              end
            end
          when "size"
            if details_mode
              entries.sort_by { |e| -e[:size] }
            else
              entries.sort_by do |e|
                full_path = File.join(base_path, e)
                File.exist?(full_path) ? -File.size(full_path) : 0
              end
            end
          when "none"
            entries
          else
            # Default to name if invalid sort_by
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
end
