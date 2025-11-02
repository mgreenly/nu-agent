# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to display help information
      class HelpCommand < BaseCommand
        # Class method to provide command description
        def self.description
          "Show this help message"
        end

        def execute(_input)
          app.console.puts("")
          app.output_lines(*help_text.lines.map(&:chomp), type: :command)
          :continue
        end

        private

        def help_text
          lines = ["Available commands:"]

          # Get all registered commands and build help dynamically
          commands = app.registered_commands
          sorted_commands = commands.keys.sort

          # Build the help text from registered commands
          sorted_commands.each do |command_name|
            command_class = commands[command_name]
            add_command_help(lines, command_name, command_class)
          end

          lines.join("\n")
        end

        def add_command_help(lines, command_name, command_class)
          details = command_details[command_name]

          if details
            add_detailed_help(lines, details)
          elsif command_class.respond_to?(:description)
            desc = command_class.description
            lines << format("  %<cmd>-30s - %<desc>s", cmd: command_name, desc: desc)
          else
            lines << format("  %<cmd>-30s - %<desc>s", cmd: command_name,
                                                       desc: "(No description available)")
          end
        end

        def add_detailed_help(lines, details)
          usage = details[:usage]
          desc_lines = details[:description]

          # Format the first line with proper padding
          first_line = format("  %<usage>-30s - %<desc>s", usage: usage, desc: desc_lines.first)
          lines << first_line

          # Add additional description lines with proper indentation
          desc_lines[1..]&.each do |desc_line|
            lines << format("  %<pad>-30s   %<desc>s", pad: "", desc: desc_line)
          end
        end

        # rubocop:disable Metrics/MethodLength
        def command_details
          @command_details ||= {
            "/backup" => {
              usage: "/backup [<destination>]",
              description: [
                "Create a backup of the conversation database",
                "  - No argument: Creates memory-YYYY-MM-DD-HHMMSS.db in current directory",
                "  - With path: Creates backup at specified location (supports ~ expansion)"
              ]
            },
            "/clear" => {
              usage: "/clear",
              description: ["Clear the screen"]
            },
            "/debug" => {
              usage: "/debug <on|off>",
              description: ["Enable/disable debug mode (show/hide tool calls and results)"]
            },
            "/exit" => {
              usage: "/exit",
              description: ["Exit the REPL"]
            },
            "/help" => {
              usage: "/help",
              description: ["Show this help message"]
            },
            "/info" => {
              usage: "/info",
              description: ["Show current session information"]
            },
            "/llm" => {
              usage: "/llm [help|verbosity [<level>]]",
              description: ["Manage LLM subsystem debugging"]
            },
            "/messages" => {
              usage: "/messages [help|verbosity [<level>]]",
              description: ["Manage Messages subsystem debugging"]
            },
            "/migrate-exchanges" => {
              usage: "/migrate-exchanges",
              description: ["Create exchanges from existing messages (one-time migration)"]
            },
            "/model" => {
              usage: "/model orchestrator <name>",
              description: [
                "Switch orchestrator model",
                "/model summarizer <name>       - Switch summarizer model"
              ]
            },
            "/models" => {
              usage: "/models",
              description: ["List available models"]
            },
            "/persona" => {
              usage: "/persona [<name>|<command>]",
              description: ["Manage agent personas (use /persona for details)"]
            },
            "/personas" => {
              usage: "/personas",
              description: ["List all available personas"]
            },
            "/rag" => {
              usage: "/rag <query>",
              description: ["Search conversation history using RAG"]
            },
            "/redaction" => {
              usage: "/redaction <on|off>",
              description: ["Enable/disable redaction of tool results in context"]
            },
            "/reset" => {
              usage: "/reset",
              description: ["Start a new conversation"]
            },
            "/search" => {
              usage: "/search [help|verbosity [<level>]]",
              description: ["Manage Search subsystem debugging"]
            },
            "/stats" => {
              usage: "/stats [help|verbosity [<level>]]",
              description: ["Manage Stats subsystem debugging"]
            },
            "/tools" => {
              usage: "/tools",
              description: ["List available tools"]
            },
            "/tools-debug" => {
              usage: "/tools-debug [help|verbosity [<level>]]",
              description: ["Manage Tools subsystem debugging"]
            },
            "/verbosity" => {
              usage: "/verbosity [<subsystem>] [<level>]",
              description: [
                "Set verbosity levels for debugging",
                "  - No arguments: Shows current verbosity levels for all subsystems",
                "  - With subsystem and level: Sets verbosity for specific subsystem"
              ]
            },
            "/worker" => {
              usage: "/worker [<name>] [<command>]",
              description: ["Manage background workers (use /worker for details)"]
            }
          }
        end
        # rubocop:enable Metrics/MethodLength
      end
    end
  end
end
