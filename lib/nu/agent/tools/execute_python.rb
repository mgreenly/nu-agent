# frozen_string_literal: true

require "open3"

module Nu
  module Agent
    module Tools
      class ExecutePython
        PARAMETERS = {
          code: {
            type: "string",
            description: "The Python code to execute",
            required: true
          },
          timeout: {
            type: "integer",
            description: "Code timeout in seconds (default: 30, max: 300)",
            required: false
          }
        }.freeze

        def name
          "execute_python"
        end

        def available?
          system("which python3 > /dev/null 2>&1")
        end

        def description
          "Execute Python code directly on the host system. " \
            "Perfect for: data analysis, scripting, calculations, file processing, API calls. " \
            "Code runs in the current working directory with full system access. " \
            "File system permissions apply normally - operations will fail with errors if permissions are insufficient."
        end

        def parameters
          PARAMETERS
        end

        def execute(arguments:, **)
          code = arguments[:code] || arguments["code"]
          timeout_seconds = arguments[:timeout] || arguments["timeout"] || 30

          raise ArgumentError, "code is required" if code.nil? || code.empty?

          # Clamp timeout to reasonable range
          timeout_seconds = timeout_seconds.to_i.clamp(1, 300)

          stdout = ""
          stderr = ""
          exit_code = nil

          begin
            # Use timeout command with python3
            cmd = ["timeout", "#{timeout_seconds}s", "python3", "-c", code]

            # Execute code
            stdout, stderr, status = Open3.capture3(*cmd, chdir: Dir.pwd)
            exit_code = status.exitstatus
          rescue StandardError => e
            stderr = "Execution failed: #{e.message}"
            exit_code = 1
          end

          # Check if command timed out (exit code 124 from timeout command)
          timed_out = (exit_code == 124)
          stderr = "Code timed out after #{timeout_seconds} seconds" if timed_out

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
