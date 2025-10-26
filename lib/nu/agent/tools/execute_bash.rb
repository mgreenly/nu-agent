# frozen_string_literal: true

require "open3"

module Nu
  module Agent
    module Tools
      class ExecuteBash
        def name
          "execute_bash"
        end

        def description
          "Execute bash commands directly on the host system. " \
            "Perfect for: system operations, running CLI tools, file operations, data processing, testing commands. " \
            "Commands run in the current working directory with full system access. " \
            "File system permissions apply normally - operations will fail with errors if permissions are insufficient."
        end

        def parameters
          {
            command: {
              type: "string",
              description: "The bash command to execute",
              required: true
            },
            timeout: {
              type: "integer",
              description: "Command timeout in seconds (default: 30, max: 300)",
              required: false
            }
          }
        end

        def execute(arguments:, history:, context:)
          command = arguments[:command] || arguments["command"]
          timeout_seconds = arguments[:timeout] || arguments["timeout"] || 30

          raise ArgumentError, "command is required" if command.nil? || command.empty?

          # Clamp timeout to reasonable range
          timeout_seconds = [[timeout_seconds.to_i, 1].max, 300].min

          # Debug output
          application = context["application"]
          if application&.debug
            application.console.puts("\e[90m[execute_bash] command: #{command}\e[0m")

            application.console.puts("\e[90m[execute_bash] timeout: #{timeout_seconds}s\e[0m")

            application.console.puts("\e[90m[execute_bash] cwd: #{Dir.pwd}\e[0m")
          end

          stdout = ""
          stderr = ""
          exit_code = nil

          begin
            # Use timeout command with bash
            cmd = ["timeout", "#{timeout_seconds}s", "bash", "-c", command]

            # Execute command
            stdout, stderr, status = Open3.capture3(*cmd, chdir: Dir.pwd)
            exit_code = status.exitstatus
          rescue StandardError => e
            stderr = "Execution failed: #{e.message}"
            exit_code = 1
          end

          # Check if command timed out (exit code 124 from timeout command)
          timed_out = (exit_code == 124)
          stderr = "Command timed out after #{timeout_seconds} seconds" if timed_out

          {
            stdout: stdout,
            stderr: stderr,
            exit_code: exit_code,
            success: exit_code.zero?,
            timed_out: timed_out
          }
        end
      end
    end
  end
end
