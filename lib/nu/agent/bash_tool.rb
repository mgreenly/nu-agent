# frozen_string_literal: true

require 'open3'

module Nu
  module Agent
    class BashTool < Tool
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
