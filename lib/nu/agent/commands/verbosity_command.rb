# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to set verbosity level (DEPRECATED)
      class VerbosityCommand < BaseCommand
        def execute(_input)
          show_deprecation_message
          :continue
        end

        private

        def show_deprecation_message
          app.console.puts("")
          app.output_line("The /verbosity command is deprecated.", type: :command)
          app.output_line("Please use subsystem-specific commands instead:", type: :command)
          app.output_line("", type: :command)
          app.output_line("  /llm verbosity <level>        - LLM debug output", type: :command)
          app.output_line("  /tools-debug verbosity <level> - Tool debug output", type: :command)
          app.output_line("  /messages verbosity <level>   - Message tracking", type: :command)
          app.output_line("  /search verbosity <level>     - Search internals", type: :command)
          app.output_line("  /stats verbosity <level>      - Statistics/costs", type: :command)
          app.output_line("  /spellcheck-debug verbosity <level> - Spell checker", type: :command)
          app.output_line("", type: :command)
          app.output_line("Use /<subsystem> help to see verbosity levels for each subsystem.", type: :command)
        end
      end
    end
  end
end
