# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class ExecuteBash
      def name
        "execute_bash"
      end

      def description
        "Execute a bash command and return the output. Use this to run shell commands, check system information, or perform file operations."
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

        # Debug output
        if application = context['application']
          cwd = Dir.pwd
          application.output.debug("[execute_bash] cwd: #{cwd}")
          application.output.debug("[execute_bash] command: #{command}")
        end

        stdout, stderr, status = Open3.capture3(command)

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
