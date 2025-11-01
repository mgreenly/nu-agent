# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to manage subsystem-specific verbosity levels
      class VerbosityCommand < BaseCommand
        SUBSYSTEMS = {
          "llm" => {
            levels: {
              0 => "No LLM debug output",
              1 => "Show warnings (empty responses, API errors)",
              2 => "Show message count and token estimates",
              3 => "Show full request messages",
              4 => "Add tool definitions to request display"
            }
          },
          "tools" => {
            levels: {
              0 => "No tool debug output",
              1 => "Show tool name only",
              2 => "Show tool name with brief arguments/results (truncated)",
              3 => "Show full arguments and full results"
            }
          },
          "messages" => {
            levels: {
              0 => "No message tracking output",
              1 => "Basic message in/out notifications",
              2 => "Add role, actor, content preview (30 chars)",
              3 => "Extended previews (100 chars)"
            }
          },
          "search" => {
            levels: {
              0 => "No search debug output",
              1 => "Show search commands being executed",
              2 => "Add search stats (files searched, matches found)"
            }
          },
          "stats" => {
            levels: {
              0 => "No statistics output",
              1 => "Show basic token/cost summary",
              2 => "Add timing, cache hit rates, detailed breakdown"
            }
          },
          "spellcheck" => {
            levels: {
              0 => "No spell checker output",
              1 => "Show spell checker requests and responses"
            }
          },
          "console" => {
            levels: {
              0 => "No console debug output",
              1 => "Show state transitions"
            }
          },
          "thread" => {
            levels: {
              0 => "No thread debug output",
              1 => "Show thread start/stop messages"
            }
          }
        }.freeze

        def execute(input)
          # Strip command name from input (e.g., "/verbosity llm 2" -> "llm 2")
          args = input.split(" ", 2)[1]
          parts = args.to_s.strip.split(/\s+/)

          case parts.length
          when 0
            show_all_subsystems
          when 1
            if parts[0] == "help"
              show_help
            else
              show_subsystem(parts[0])
            end
          when 2
            set_subsystem_verbosity(parts[0], parts[1])
          else
            show_error
          end

          :continue
        end

        private

        def show_all_subsystems
          app.console.puts("")
          SUBSYSTEMS.keys.sort.each do |subsystem|
            level = load_verbosity(subsystem)
            max_level = SUBSYSTEMS[subsystem][:levels].keys.max
            app.output_line("/verbosity #{subsystem} (0-#{max_level}) = #{level}", type: :command)
          end
        end

        def show_subsystem(subsystem)
          unless SUBSYSTEMS.key?(subsystem)
            show_unknown_subsystem(subsystem)
            return
          end

          level = load_verbosity(subsystem)
          max_level = SUBSYSTEMS[subsystem][:levels].keys.max
          app.console.puts("")
          app.output_line("/verbosity #{subsystem} (0-#{max_level}) = #{level}", type: :command)
        end

        def set_subsystem_verbosity(subsystem, level_str)
          unless SUBSYSTEMS.key?(subsystem)
            show_unknown_subsystem(subsystem)
            return
          end

          level = Integer(level_str)
          if level.negative?
            show_error("Level must be non-negative")
            return
          end

          config_key = "#{subsystem}_verbosity"
          app.history.set_config(config_key, level_str)
          app.console.puts("")
          app.output_line("#{config_key}=#{level}", type: :command)
        rescue ArgumentError
          show_error("Level must be a number")
        end

        def load_verbosity(subsystem)
          config_key = "#{subsystem}_verbosity"
          app.history.get_int(config_key, default: 0)
        end

        def show_help
          app.console.puts("")
          show_help_header
          show_help_usage
          show_help_subsystems
        end

        def show_help_header
          app.output_line("Subsystem Verbosity Control", type: :command)
          app.output_line("", type: :command)
        end

        def show_help_usage
          app.output_line("Usage:", type: :command)
          app.output_line("  /verbosity                    - Show all subsystem levels", type: :command)
          app.output_line("  /verbosity <subsystem>        - Show specific subsystem level", type: :command)
          app.output_line("  /verbosity <subsystem> <level> - Set subsystem level", type: :command)
          app.output_line("  /verbosity help               - Show this help", type: :command)
          app.output_line("", type: :command)
        end

        def show_help_subsystems
          app.output_line("Available subsystems:", type: :command)
          app.output_line("", type: :command)

          SUBSYSTEMS.keys.sort.each do |subsystem|
            show_subsystem_help(subsystem)
          end
        end

        def show_subsystem_help(subsystem)
          max_level = SUBSYSTEMS[subsystem][:levels].keys.max
          app.output_line("#{subsystem} (0-#{max_level}):", type: :command)
          SUBSYSTEMS[subsystem][:levels].sort.each do |level, description|
            app.output_line("  #{level}: #{description}", type: :command)
          end
          app.output_line("", type: :command)
        end

        def show_unknown_subsystem(subsystem)
          app.console.puts("")
          app.output_line("Unknown subsystem: #{subsystem}", type: :command)
          app.output_line("Available subsystems: #{SUBSYSTEMS.keys.sort.join(', ')}", type: :command)
          app.output_line("Use: /verbosity help", type: :command)
        end

        def show_error(message = nil)
          app.console.puts("")
          app.output_line("Error: #{message}", type: :command) if message
          app.output_line("Usage:", type: :command)
          app.output_line("  /verbosity                    - Show all subsystem levels", type: :command)
          app.output_line("  /verbosity <subsystem>        - Show specific subsystem level", type: :command)
          app.output_line("  /verbosity <subsystem> <level> - Set subsystem level", type: :command)
          app.output_line("  /verbosity help               - Show detailed help", type: :command)
        end
      end
    end
  end
end
