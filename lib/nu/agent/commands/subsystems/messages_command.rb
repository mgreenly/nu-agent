# frozen_string_literal: true

require_relative "subsystem_command"

module Nu
  module Agent
    module Commands
      module Subsystems
        # Command for controlling Messages subsystem debug verbosity
        class MessagesCommand < SubsystemCommand
          def self.description
            "Manage Messages subsystem debugging"
          end

          def initialize(application)
            super(application, "messages", "messages_verbosity")
          end

          protected

          def show_help
            app.console.puts("")
            app.output_lines(*help_text.lines.map(&:chomp), type: :command)
          end

          def help_text
            <<~HELP
              Messages Subsystem

              Controls debug output for message tracking and routing.

              Commands:
                /messages verbosity <level>  - Set verbosity level
                /messages verbosity          - Show current verbosity level
                /messages help               - Show this help

              Verbosity Levels:
                0 - No message tracking output
                1 - Basic message in/out notifications
                2 - Add role, actor, content preview (30 chars)
                3 - Extended previews (100 chars)
                4+ - Reserved for future (full content display)
            HELP
          end
        end
      end
    end
  end
end
