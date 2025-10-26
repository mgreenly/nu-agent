# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileRead
        def name
          "file_read"
        end

        def description
          "PREFERRED tool for reading file contents. Use this instead of execute_bash with cat/head/tail commands. " \
            "Returns file content with line numbers (cat -n style) for easy code references. " \
            "Perfect for examining specific files when you know the file path.\n" \
            "\nSupports flexible line range options:\n" \
            "- Read entire file (default, up to 2000 lines)\n" \
            "- Read specific range: start_line=10, end_line=50\n" \
            "- Read from offset: offset=100, limit=50 (50 lines starting at line 100)\n" \
            "- Read first N lines: limit=100\n" \
            "\nCommon use cases: Read configuration files, examine source code, check file contents, " \
            "review specific sections of large files. " \
            "Use file_glob to FIND files by pattern, use file_grep to SEARCH within file contents, " \
            "use file_read to READ a specific known file."
        end

        def parameters
          {
            file: {
              type: "string",
              description: "Path to the file to read (relative to project root or absolute)",
              required: true
            },
            start_line: {
              type: "integer",
              description: "Starting line number to read from (1-indexed). Use with end_line for range.",
              required: false
            },
            end_line: {
              type: "integer",
              description: "Ending line number to read to (1-indexed, inclusive). Use with start_line for range.",
              required: false
            },
            offset: {
              type: "integer",
              description: "Starting line number (0-indexed). Use with limit for offset-based reading.",
              required: false
            },
            limit: {
              type: "integer",
              description: "Maximum number of lines to read (default: 2000). Can combine with offset.",
              required: false
            },
            show_line_numbers: {
              type: "boolean",
              description: "Include line numbers in output like 'cat -n' (default: true)",
              required: false
            }
          }
        end

        def execute(arguments:, history:, context:)
          file_path = arguments[:file] || arguments["file"]
          start_line = arguments[:start_line] || arguments["start_line"]
          end_line = arguments[:end_line] || arguments["end_line"]
          offset = arguments[:offset] || arguments["offset"]
          limit = arguments[:limit] || arguments["limit"] || 2000
          show_line_numbers = arguments[:show_line_numbers] || arguments["show_line_numbers"]
          show_line_numbers = true if show_line_numbers.nil? # Default to true

          # Validate required parameters
          if file_path.nil? || file_path.empty?
            return {
              error: "file path is required",
              content: nil
            }
          end

          # Resolve file path
          resolved_path = resolve_path(file_path)

          # Debug output
          application = context["application"]
          if application&.debug
            application.console.puts("\e[90m[file_read] file: #{resolved_path}\e[0m")
            application.console.puts("\e[90m[file_read] range: start=#{start_line}, end=#{end_line}, offset=#{offset}, limit=#{limit}\e[0m")
          end

          begin
            # Check if file exists and is readable
            unless File.exist?(resolved_path)
              return {
                error: "File not found: #{file_path}",
                content: nil
              }
            end

            unless File.file?(resolved_path)
              return {
                error: "Not a file: #{file_path}",
                content: nil
              }
            end

            unless File.readable?(resolved_path)
              return {
                error: "File not readable: #{file_path}",
                content: nil
              }
            end

            # Read file lines
            lines = File.readlines(resolved_path)
            total_lines = lines.length

            # Determine which lines to return
            selected_lines = if start_line && end_line
                               # Range: start_line to end_line (1-indexed, inclusive)
                               # Clamp to valid range instead of erroring
                               start_idx = [[start_line - 1, 0].max, total_lines - 1].min
                               end_idx = [[end_line - 1, 0].max, total_lines - 1].min

                               # Return empty if start is beyond file
                               if start_line - 1 >= total_lines
                                 []
                               else
                                 lines[start_idx..end_idx]
                               end
                             elsif offset
                               # Offset-based (0-indexed)
                               # Return empty if offset is beyond file, otherwise return what exists
                               if offset >= total_lines
                                 []
                               else
                                 lines[offset, limit] || []
                               end
                             else
                               # Just limit (from beginning)
                               lines.take(limit)
                             end

            # Format with line numbers if requested
            if show_line_numbers
              # Calculate starting line number for display
              first_line_num = if start_line
                                 start_line
                               elsif offset
                                 offset + 1 # Convert 0-indexed to 1-indexed
                               else
                                 1
                               end

              # Format like cat -n (line number, tab, content)
              formatted_lines = selected_lines.each_with_index.map do |line, idx|
                line_num = first_line_num + idx
                # Right-align line numbers to 6 characters, then tab, then content
                format("%6d\t%s", line_num, line)
              end

              content = formatted_lines.join
            else
              content = selected_lines.join
            end

            {
              file: file_path,
              total_lines: total_lines,
              lines_read: selected_lines.length,
              content: content,
              truncated: selected_lines.length >= limit && selected_lines.length < total_lines
            }
          rescue StandardError => e
            {
              error: "Failed to read file: #{e.message}",
              content: nil
            }
          end
        end

        private

        def resolve_path(file_path)
          # If relative path, make it relative to current directory
          if file_path.start_with?("/")
            File.expand_path(file_path)
          else
            File.expand_path(file_path, Dir.pwd)
          end
        end
      end
    end
  end
end
