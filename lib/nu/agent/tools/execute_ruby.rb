# frozen_string_literal: true

require 'tempfile'

module Nu
  module Agent
    module Tools
      class ExecuteRuby
        def name
          "execute_ruby"
        end

        def description
          <<~DESC
            Execute a Ruby script and return the output. This is the PREFERRED scripting tool for:
            - Complex data processing and manipulation
            - File operations using Ruby's File/FileUtils libraries
            - Working with structured data (JSON, YAML, CSV, etc.)
            - String manipulation and text processing
            - Access to all installed Ruby gems
            - Multi-line logic and control flow

            The script is executed from the current working directory and has access to all
            Ruby standard libraries and installed gems.

            Use this instead of bash for complex operations that benefit from Ruby's expressiveness.
          DESC
        end

        def parameters
          {
            script: {
              type: "string",
              description: "The Ruby script to execute",
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
            # Create temp file in /tmp with .rb extension
            temp_file = Tempfile.new(['ruby_script_', '.rb'], '/tmp')
            temp_file.write(script)
            temp_file.close

            # Execute the Ruby script from the current working directory
            # Use the same ruby interpreter that's running this code
            ruby_executable = RbConfig.ruby
            stdout, stderr, status = Open3.capture3(ruby_executable, temp_file.path, chdir: Dir.pwd)

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
