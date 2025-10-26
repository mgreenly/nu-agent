# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to toggle redaction mode
      class RedactionCommand < BaseCommand
        def execute(input)
          parts = input.split(" ", 2)
          if parts.length < 2 || parts[1].strip.empty?
            app.console.puts("")
            app.output_line("Usage: /redaction <on|off>", type: :debug)
            app.output_line("Current: redaction=#{app.redact ? 'on' : 'off'}", type: :debug)
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == "on"
            app.redact = true
            app.history.set_config("redaction", "true")
            app.console.puts("")
            app.output_line("redaction=on", type: :debug)
          elsif setting == "off"
            app.redact = false
            app.history.set_config("redaction", "false")
            app.console.puts("")
            app.output_line("redaction=off", type: :debug)
          else
            app.console.puts("")
            app.output_line("Invalid option. Use: /redaction <on|off>", type: :debug)
          end

          :continue
        end
      end
    end
  end
end
