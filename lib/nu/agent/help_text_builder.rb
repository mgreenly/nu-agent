# frozen_string_literal: true

module Nu
  module Agent
    # Builds the help text for available commands
    class HelpTextBuilder
      def self.build
        <<~HELP
          Available commands:
            /clear                         - Clear the screen
            /debug <on|off>                - Enable/disable debug mode (show/hide tool calls and results)
            /exit                          - Exit the REPL
            /fix                           - Scan and fix database corruption issues
            /help                          - Show this help message
            /index-man <on|off|reset>      - Enable/disable background man page indexing, or reset database
            /info                          - Show current session information
            /migrate-exchanges             - Create exchanges from existing messages (one-time migration)
            /model orchestrator <name>     - Switch orchestrator model
            /model spellchecker <name>     - Switch spellchecker model
            /model summarizer <name>       - Switch summarizer model
            /models                        - List available models
            /redaction <on|off>            - Enable/disable redaction of tool results in context
            /reset                         - Start a new conversation
            /spellcheck <on|off>           - Enable/disable automatic spell checking of user input
            /summarizer <on|off>           - Enable/disable background conversation summarization
            /tools                         - List available tools

          Debug Subsystems:
            /llm verbosity <level>              - Control LLM API debug output
            /tools-debug verbosity <level>      - Control tool call/result debug output
            /messages verbosity <level>         - Control message tracking debug output
            /search verbosity <level>           - Control search internals debug output
            /stats verbosity <level>            - Control statistics/cost debug output
            /spellcheck-debug verbosity <level> - Control spell checker debug output

            Use /<subsystem> help for details on verbosity levels
        HELP
      end
    end
  end
end
