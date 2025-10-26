# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to toggle summarizer mode
      class SummarizerCommand < BaseCommand
        def execute(input)
          parts = input.split(" ", 2)
          if parts.length < 2 || parts[1].strip.empty?
            app.console.puts("")
            app.output_line("Usage: /summarizer <on|off>", type: :debug)
            app.output_line("Current: summarizer=#{app.summarizer_enabled ? 'on' : 'off'}", type: :debug)
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == "on"
            app.summarizer_enabled = true
            app.history.set_config("summarizer_enabled", "true")
            app.console.puts("")
            app.output_line("summarizer=on", type: :debug)
            app.output_line("Summarizer will start on next /reset", type: :debug)
          elsif setting == "off"
            app.summarizer_enabled = false
            app.history.set_config("summarizer_enabled", "false")
            app.console.puts("")
            app.output_line("summarizer=off", type: :debug)
          else
            app.console.puts("")
            app.output_line("Invalid option. Use: /summarizer <on|off>", type: :debug)
          end

          :continue
        end
      end
    end
  end
end
