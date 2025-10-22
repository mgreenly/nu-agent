# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class FileEditor
        def name
          "edit_file"
        end

        def description
          <<~DESC
            Edit files in the project directory. Supports read, write, append, and replace operations.

            Actions:
            - read: Read file content (optionally specify start_line and end_line)
            - write: Write/overwrite file content
            - append: Append content to end of file
            - replace: Replace all occurrences of old_text with new_text (literal string matching)

            Safety: Only files within the current project directory can be edited.
          DESC
        end

        def parameters
          {
            action: {
              type: "string",
              description: "Action to perform: 'read', 'write', 'append', or 'replace'",
              required: true
            },
            file: {
              type: "string",
              description: "Path to the file (relative to project root or absolute within project)",
              required: true
            },
            content: {
              type: "string",
              description: "Content for write/append actions",
              required: false
            },
            old_text: {
              type: "string",
              description: "Text to find for replace action",
              required: false
            },
            new_text: {
              type: "string",
              description: "Text to replace with for replace action",
              required: false
            },
            start_line: {
              type: "integer",
              description: "Starting line number for read action (1-indexed)",
              required: false
            },
            end_line: {
              type: "integer",
              description: "Ending line number for read action (1-indexed)",
              required: false
            }
          }
        end

        def execute(arguments:, history:, context:)
          action = arguments[:action] || arguments["action"]
          file_path = arguments[:file] || arguments["file"]

          raise ArgumentError, "action is required" if action.nil? || action.empty?
          raise ArgumentError, "file is required" if file_path.nil? || file_path.empty?

          # Validate action
          valid_actions = %w[read write append replace]
          unless valid_actions.include?(action)
            raise ArgumentError, "Invalid action '#{action}'. Must be one of: #{valid_actions.join(', ')}"
          end

          # Resolve and validate file path
          file_path = resolve_path(file_path)
          validate_path(file_path)

          # Execute the action
          case action
          when "read"
            execute_read(file_path, arguments)
          when "write"
            execute_write(file_path, arguments)
          when "append"
            execute_append(file_path, arguments)
          when "replace"
            execute_replace(file_path, arguments)
          end
        rescue => e
          {
            status: "error",
            error: e.message
          }
        end

        private

        def resolve_path(file_path)
          # If relative path, make it relative to current directory
          if file_path.start_with?('/')
            File.expand_path(file_path)
          else
            File.expand_path(file_path, Dir.pwd)
          end
        end

        def validate_path(file_path)
          # Get the project root (current working directory)
          project_root = File.expand_path(Dir.pwd)

          # Ensure the file path is within the project directory
          unless file_path.start_with?(project_root)
            raise ArgumentError, "Access denied: File must be within project directory (#{project_root})"
          end

          # Prevent directory traversal attacks
          if file_path.include?('..')
            raise ArgumentError, "Access denied: Path cannot contain '..'"
          end
        end

        def execute_read(file_path, arguments)
          unless File.exist?(file_path)
            raise ArgumentError, "File not found: #{file_path}"
          end

          unless File.readable?(file_path)
            raise ArgumentError, "File not readable: #{file_path}"
          end

          content = File.read(file_path)
          lines = content.lines

          # Handle line range if specified
          start_line = arguments[:start_line] || arguments["start_line"]
          end_line = arguments[:end_line] || arguments["end_line"]

          if start_line || end_line
            start_idx = (start_line || 1) - 1
            end_idx = (end_line || lines.length) - 1

            if start_idx < 0 || start_idx >= lines.length
              raise ArgumentError, "Invalid start_line: #{start_line}"
            end

            if end_idx < 0 || end_idx >= lines.length
              raise ArgumentError, "Invalid end_line: #{end_line}"
            end

            lines = lines[start_idx..end_idx]
          end

          {
            status: "success",
            action: "read",
            file: file_path,
            content: lines.join,
            total_lines: File.read(file_path).lines.length,
            lines_read: lines.length
          }
        end

        def execute_write(file_path, arguments)
          content = arguments[:content] || arguments["content"]
          raise ArgumentError, "content is required for write action" if content.nil?

          # Create directory if it doesn't exist
          dir = File.dirname(file_path)
          FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

          # Write the file
          File.write(file_path, content)

          {
            status: "success",
            action: "write",
            file: file_path,
            bytes_written: content.bytesize,
            lines_written: content.lines.length
          }
        end

        def execute_append(file_path, arguments)
          content = arguments[:content] || arguments["content"]
          raise ArgumentError, "content is required for append action" if content.nil?

          unless File.exist?(file_path)
            raise ArgumentError, "File not found: #{file_path}. Use 'write' action to create new files."
          end

          # Append to file
          File.open(file_path, 'a') do |file|
            file.write(content)
          end

          {
            status: "success",
            action: "append",
            file: file_path,
            bytes_appended: content.bytesize,
            lines_appended: content.lines.length
          }
        end

        def execute_replace(file_path, arguments)
          old_text = arguments[:old_text] || arguments["old_text"]
          new_text = arguments[:new_text] || arguments["new_text"]

          raise ArgumentError, "old_text is required for replace action" if old_text.nil? || old_text.empty?
          raise ArgumentError, "new_text is required for replace action" if new_text.nil?

          unless File.exist?(file_path)
            raise ArgumentError, "File not found: #{file_path}"
          end

          # Read the file
          content = File.read(file_path)

          # Count occurrences before replacement
          occurrences = content.scan(old_text).length

          if occurrences == 0
            return {
              status: "success",
              action: "replace",
              file: file_path,
              replacements: 0,
              message: "No occurrences of '#{old_text}' found"
            }
          end

          # Perform literal string replacement
          new_content = content.gsub(old_text, new_text)

          # Write back
          File.write(file_path, new_content)

          {
            status: "success",
            action: "replace",
            file: file_path,
            replacements: occurrences,
            old_text: old_text,
            new_text: new_text
          }
        end
      end
    end
  end
end
