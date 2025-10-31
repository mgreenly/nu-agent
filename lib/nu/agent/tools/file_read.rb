# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileRead
        PARAMETERS = {
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
        }.freeze

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

          return error_response("file path is required") if args[:file_path].nil? || args[:file_path].empty?

          resolved_path = resolve_path(args[:file_path])

          begin
            error = validate_file(resolved_path, args[:file_path])
            return error if error

            lines = File.readlines(resolved_path)
            selected_lines = select_lines(lines, args)
            content = format_content(selected_lines, args)

            build_success_response(args[:file_path], lines.length, selected_lines.length, content, args[:limit])
          rescue StandardError => e
            error_response("Failed to read file: #{e.message}")
          end
        end

        private

        def parse_arguments(arguments)
          show_line_nums = if arguments.key?(:show_line_numbers)
                             arguments[:show_line_numbers]
                           else
                             arguments["show_line_numbers"]
                           end
          show_line_nums = true if show_line_nums.nil?

          {
            file_path: arguments[:file] || arguments["file"],
            start_line: arguments[:start_line] || arguments["start_line"],
            end_line: arguments[:end_line] || arguments["end_line"],
            offset: arguments[:offset] || arguments["offset"],
            limit: arguments[:limit] || arguments["limit"] || 2000,
            show_line_numbers: show_line_nums
          }
        end

        def error_response(message)
          { error: message, content: nil }
        end

        def validate_file(resolved_path, file_path)
          return error_response("File not found: #{file_path}") unless File.exist?(resolved_path)
          return error_response("Not a file: #{file_path}") unless File.file?(resolved_path)
          return error_response("File not readable: #{file_path}") unless File.readable?(resolved_path)

          nil
        end

        def select_lines(lines, args)
          total_lines = lines.length

          if args[:start_line] && args[:end_line]
            select_line_range(lines, args[:start_line], args[:end_line], total_lines)
          elsif args[:offset]
            select_lines_from_offset(lines, args[:offset], args[:limit], total_lines)
          else
            lines.take(args[:limit])
          end
        end

        def select_line_range(lines, start_line, end_line, total_lines)
          return [] if start_line - 1 >= total_lines

          start_idx = (start_line - 1).clamp(0, total_lines - 1)
          end_idx = (end_line - 1).clamp(0, total_lines - 1)
          lines[start_idx..end_idx]
        end

        def select_lines_from_offset(lines, offset, limit, total_lines)
          return [] if offset >= total_lines

          lines[offset, limit] || []
        end

        def format_content(selected_lines, args)
          return selected_lines.join unless args[:show_line_numbers]

          first_line_num = calculate_first_line_number(args)
          format_with_line_numbers(selected_lines, first_line_num)
        end

        def calculate_first_line_number(args)
          return args[:start_line] if args[:start_line]
          return args[:offset] + 1 if args[:offset]

          1
        end

        def format_with_line_numbers(lines, first_line_num)
          formatted_lines = lines.each_with_index.map do |line, idx|
            line_num = first_line_num + idx
            format("%<num>6d\t%<line>s", num: line_num, line: line)
          end
          formatted_lines.join
        end

        def build_success_response(file_path, total_lines, lines_read, content, limit)
          {
            file: file_path,
            total_lines: total_lines,
            lines_read: lines_read,
            content: content,
            truncated: lines_read >= limit && lines_read < total_lines
          }
        end

        def resolve_path(file_path)
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
