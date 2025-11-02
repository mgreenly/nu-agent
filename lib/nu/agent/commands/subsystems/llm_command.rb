# frozen_string_literal: true

require_relative "subsystem_command"

module Nu
  module Agent
    module Commands
      module Subsystems
        # Command for controlling LLM subsystem debug verbosity
        class LlmCommand < SubsystemCommand
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
                4 - + Tool definitions
                5 - + Complete message history
            HELP
          end
        end
      end
    end
  end
end
