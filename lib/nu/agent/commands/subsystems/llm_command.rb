# frozen_string_literal: true

require_relative "subsystem_command"

module Nu
  module Agent
    module Commands
      module Subsystems
        # Command for controlling LLM subsystem debug verbosity
        class LlmCommand < SubsystemCommand
          def self.description
            "Manage LLM subsystem debugging"
          end

          def initialize(application)
            super(application, "llm", "llm_verbosity")
          end

          protected

          def show_help
            app.console.puts("")
            app.output_lines(*help_text.lines.map(&:chomp), type: :command)
          end

          def help_text
            <<~HELP
              LLM Subsystem

              Controls debug output for LLM API interactions.

              Commands:
                /llm verbosity <level>  - Set verbosity level
                /llm verbosity          - Show current verbosity level
                /llm help               - Show this help

              Verbosity Levels:
                0 - No LLM debug output
                1 - Show final user message only
                2 - + System prompt
                3 - + RAG content (redactions, spell check)
                4 - + Tool list (names with first sentence)
                5 - + Tool definitions (complete schemas)
                6 - + Complete message history
            HELP
          end
        end
      end
    end
  end
end
