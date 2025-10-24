# frozen_string_literal: true

require 'tempfile'

module Nu
  module Agent
    module Tools
      class ExecuteJavascript
        def name
          "execute_javascript"
        end

        def description
          "PREFERRED tool for script generation and execution. " \
          "Execute JavaScript code using Deno for: data processing, file operations, API calls, JSON/text manipulation, web scraping, and any computational tasks. " \
          "Has access to Deno standard library and can import npm packages. " \
          "Has full internet access and can make HTTP/HTTPS requests using fetch API. " \
          "Code execution is sandboxed with read/write access limited to the current working directory. " \
          "Supports modern JavaScript features including async/await, fetch API, and ES modules."
        end

        def parameters
          {
            script: {
              type: "string",
              description: "The JavaScript script to execute",
              required: true
            }
          }
        end

        def execute(arguments:, history:, context:)
          script = arguments[:script] || arguments["script"]

          raise ArgumentError, "script is required" if script.nil? || script.empty?

          # Create a temporary file for the script
          temp_file = nil
          stdout = ""
          stderr = ""
          status = nil

          begin
            # Create temp file in /tmp with .js extension
            temp_file = Tempfile.new(['javascript_script_', '.js'], '/tmp')
            temp_file.write(script)
            temp_file.close

            # Debug output
            if application = context['application']
              cwd = Dir.pwd
              application.output.debug("[execute_javascript] tempfile: #{temp_file.path}")
              application.output.debug("[execute_javascript] cwd: #{cwd}")
            end

            # Execute the JavaScript script from the current working directory
            # Permissions: read/write limited to current directory, full network access
            deno_path = File.join(Dir.home, '.deno', 'bin', 'deno')
            stdout, stderr, status = Open3.capture3(
              deno_path,
              'run',
              '--allow-read=.',
              '--allow-write=.',
              '--allow-net',
              temp_file.path,
              chdir: Dir.pwd
            )

          ensure
            # Always clean up the temporary file
            if temp_file
              temp_file.close unless temp_file.closed?
              temp_file.unlink
            end
          end

          {
            stdout: stdout,
            stderr: stderr,
            exit_code: status.exitstatus,
            success: status.success?
          }
        end
      end
    end
  end
end
