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
            show_usage
            return :continue
          end

          update_redaction(parts[1].strip.downcase)
          :continue
        end

        private

        def show_usage
          app.console.puts("")
          app.output_line("Usage: /redaction <on|off>", type: :debug)
          app.output_line("Current: redaction=#{app.redact ? 'on' : 'off'}", type: :debug)
        end

        def update_redaction(setting)
          case setting
          when "on"
            apply_redaction_setting(true, "true", "on")
          when "off"
            apply_redaction_setting(false, "false", "off")
          else
            app.console.puts("")
            app.output_line("Invalid option. Use: /redaction <on|off>", type: :debug)
          end
        end

        def apply_redaction_setting(enabled, config_value, display_value)
          app.redact = enabled
          app.history.set_config("redaction", config_value)
          app.console.puts("")
          app.output_line("redaction=#{display_value}", type: :debug)
        end
      end
    end
  end
end
