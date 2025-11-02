# frozen_string_literal: true

require_relative "subsystem_command"

module Nu
  module Agent
    module Commands
      module Subsystems
        # Command for controlling Tools subsystem debug verbosity
        # Note: Uses "tools-debug" command name to avoid conflict with existing /tools command
        class ToolsDebugCommand < SubsystemCommand
          def self.description
            "Manage Tools subsystem debugging"
          end

          def initialize(application)
            super(application, "tools-debug", "tools_verbosity")
          end

          protected

          def show_help
            app.console.puts("")
            app.output_lines(*help_text.lines.map(&:chomp), type: :command)
          end

          def help_text
            <<~HELP
              Tools Debug Subsystem

              Controls debug output for tool invocations and results.

              Commands:
                /tools-debug verbosity <level>  - Set verbosity level
                /tools-debug verbosity          - Show current verbosity level
                /tools-debug help               - Show this help

              Verbosity Levels:
                0 - No tool debug output
                1 - Show tool name only for calls and results
                2 - Show tool name with brief arguments/results (truncated)
                3 - Show full arguments and full results (no truncation)
                4+ - Reserved for future (timing, caching info)
            HELP
          end
        end
      end
    end
  end
end
