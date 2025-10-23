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
          "Execute Ruby code. " \
          "Preferred for complex data processing, structured data (JSON/YAML/CSV), string manipulation, and multi-line logic. " \
          "Has access to all Ruby standard libraries and installed gems. Use instead of bash for operations that benefit from Ruby's expressiveness."
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

            # Debug output
            if application = context['application']
              cwd = Dir.pwd
              application.output.debug("[execute_ruby] tempfile: #{temp_file.path}")
              application.output.debug("[execute_ruby] cwd: #{cwd}")
            end

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
