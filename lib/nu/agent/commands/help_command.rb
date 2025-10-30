# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to display help information
      class HelpCommand < BaseCommand
        def execute(_input)
          app.console.puts("")
          app.output_lines(*help_text.lines.map(&:chomp), type: :command)
          :continue
        end

        private

        def help_text
          <<~HELP
            Available commands:
              /clear                         - Clear the screen
              /debug <on|off>                - Enable/disable debug mode (show/hide tool calls and results)
              /exit                          - Exit the REPL
              /help                          - Show this help message
              /info                          - Show current session information
              /migrate-exchanges             - Create exchanges from existing messages (one-time migration)
              /model orchestrator <name>     - Switch orchestrator model
              /model spellchecker <name>     - Switch spellchecker model
              /model summarizer <name>       - Switch summarizer model
              /models                        - List available models
              /rag <query>                   - Search conversation history using RAG
              /redaction <on|off>            - Enable/disable redaction of tool results in context
              /reset                         - Start a new conversation
              /spellcheck <on|off>           - Enable/disable automatic spell checking of user input
              /tools                         - List available tools
              /verbosity <number>            - Set verbosity level for debug output (default: 0)
                                               - Level 0: Thread lifecycle events + tool names only
                                               - Level 1: Level 0 + truncated tool call/result params (30 chars)
                                               - Level 2: Level 1 + message creation notifications
                                               - Level 3: Level 2 + message role/actor + truncated content/params (30 chars)
                                               - Level 4: Level 3 + full tool params + messages sent to LLM
                                               - Level 5: Level 4 + tools array
                                               - Level 6: Level 5 + longer message content previews (100 chars)
              /worker [<name>] [<command>]   - Manage background workers (use /worker for details)
          HELP
        end
      end
    end
  end
end
