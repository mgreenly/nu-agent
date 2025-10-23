# frozen_string_literal: true

require 'tempfile'

module Nu
  module Agent
    module Tools
      class ExecutePython
        def name
          "execute_python"
        end

        def description
          "Execute Python code. " \
          "Preferred for data science, scientific computing, machine learning, and numerical operations. " \
          "Has access to Python standard library and common packages (numpy, pandas, etc if installed). " \
          "Use instead of bash for operations that benefit from Python's extensive ecosystem."
        end

        def parameters
          {
            script: {
              type: "string",
              description: "The Python script to execute",
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
            # Create temp file in /tmp with .py extension
            temp_file = Tempfile.new(['python_script_', '.py'], '/tmp')
            temp_file.write(script)
            temp_file.close

            # Debug output
            if application = context['application']
              cwd = Dir.pwd
              application.output.debug("[execute_python] tempfile: #{temp_file.path}")
              application.output.debug("[execute_python] cwd: #{cwd}")
            end

            # Execute the Python script from the current working directory
            stdout, stderr, status = Open3.capture3('python3', temp_file.path, chdir: Dir.pwd)

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
