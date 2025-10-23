# frozen_string_literal: true

require 'tempfile'

module Nu
  module Agent
    module Tools
      class ExecuteBash
      def name
        "execute_bash"
      end

      def description
        "Execute bash commands. " \
        "Use this to run shell commands, check system information, or perform operations not covered by specialized tools."
      end

      def parameters
        {
          command: {
            type: "string",
            description: "The bash command to execute",
            required: true
          }
        }
      end

      def execute(arguments:, history:, context:)
        command = arguments[:command] || arguments["command"]

        raise ArgumentError, "command is required" if command.nil? || command.empty?

        # Create a temporary file for the script
        temp_file = nil
        stdout = ""
        stderr = ""
        status = nil

        begin
          # Create temp file in /tmp with .sh extension
          temp_file = Tempfile.new(['bash_script_', '.sh'], '/tmp')
          temp_file.write(command)
          temp_file.close

          # Debug output
          if application = context['application']
            cwd = Dir.pwd
            application.output.debug("[execute_bash] tempfile: #{temp_file.path}")
            application.output.debug("[execute_bash] cwd: #{cwd}")
          end

          # Execute the bash script from the current working directory
          stdout, stderr, status = Open3.capture3('bash', temp_file.path, chdir: Dir.pwd)

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
