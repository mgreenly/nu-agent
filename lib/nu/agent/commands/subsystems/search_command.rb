# frozen_string_literal: true

require_relative "subsystem_command"

module Nu
  module Agent
    module Commands
      module Subsystems
        # Command for controlling Search subsystem debug verbosity
        class SearchCommand < SubsystemCommand
          def initialize(application)
            super(application, "search", "search_verbosity")
          end

          protected

          def show_help
            app.console.puts("")
            app.output_lines(*help_text.lines.map(&:chomp), type: :command)
          end

          def help_text
            <<~HELP
              Search Subsystem

              Controls debug output for search tool internals.

              Commands:
                /search verbosity <level>  - Set verbosity level
                /search verbosity          - Show current verbosity level
                /search help               - Show this help

              Verbosity Levels:
                0 - No search debug output
                1 - Show search commands being executed (ripgrep, etc.)
                2 - Add search stats (files searched, matches found)
                3+ - Reserved for future (timing, pattern details)
            HELP
          end
        end
      end
    end
  end
end
