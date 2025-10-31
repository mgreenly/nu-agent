# frozen_string_literal: true

require_relative "subsystem_command"

module Nu
  module Agent
    module Commands
      module Subsystems
        # Command for controlling Spellcheck subsystem debug verbosity
        # Note: Uses "spellcheck-debug" command name to avoid conflict with existing /spellcheck command
        class SpellcheckDebugCommand < SubsystemCommand
          def initialize(application)
            super(application, "spellcheck-debug", "spellcheck_verbosity")
          end

          protected

          def show_help
            app.console.puts("")
            app.output_lines(*help_text.lines.map(&:chomp), type: :command)
          end

          def help_text
            <<~HELP
              Spellcheck Debug Subsystem

              Controls debug output for spell checker activity.

              Commands:
                /spellcheck-debug verbosity <level>  - Set verbosity level
                /spellcheck-debug verbosity          - Show current verbosity level
                /spellcheck-debug help               - Show this help

              Verbosity Levels:
                0 - No spell checker output (even in debug mode)
                1 - Show spell checker requests and responses
                2+ - Reserved for future (correction details, confidence scores)
            HELP
          end
        end
      end
    end
  end
end
