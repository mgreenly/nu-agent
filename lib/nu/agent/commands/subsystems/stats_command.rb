# frozen_string_literal: true

require_relative "subsystem_command"

module Nu
  module Agent
    module Commands
      module Subsystems
        # Command for controlling Stats subsystem debug verbosity
        class StatsCommand < SubsystemCommand
          def initialize(application)
            super(application, "stats", "stats_verbosity")
          end

          protected

          def show_help
            app.console.puts("")
            app.output_lines(*help_text.lines.map(&:chomp), type: :command)
          end

          def help_text
            <<~HELP
              Stats Subsystem

              Controls debug output for statistics, timing, and costs.

              Commands:
                /stats verbosity <level>  - Set verbosity level
                /stats verbosity          - Show current verbosity level
                /stats help               - Show this help

              Verbosity Levels:
                0 - No statistics output
                1 - Show basic token/cost summary after operations
                2 - Add timing, cache hit rates, detailed breakdown
                3+ - Reserved for future (per-operation metrics)
            HELP
          end
        end
      end
    end
  end
end
