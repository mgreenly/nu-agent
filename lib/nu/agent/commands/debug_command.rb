# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to toggle debug mode
      class DebugCommand < BaseCommand
        def execute(input)
          parts = input.split(" ", 2)
          if parts.length < 2 || parts[1].strip.empty?
            show_usage
            return :continue
          end

          update_debug(parts[1].strip.downcase)
          :continue
        end

        private

        def show_usage
          app.console.puts("\e[90mUsage: /debug <on|off>\e[0m")
          app.console.puts("\e[90mCurrent: debug=#{app.debug ? 'on' : 'off'}\e[0m")
        end

        def update_debug(setting)
          case setting
          when "on"
            apply_debug_setting(true, "true", "on")
          when "off"
            apply_debug_setting(false, "false", "off")
          else
            app.console.puts("\e[90mInvalid option. Use: /debug <on|off>\e[0m")
          end
        end

        def apply_debug_setting(enabled, config_value, display_value)
          app.debug = enabled
          app.console.debug = enabled
          app.formatter.debug = enabled
          app.history.set_config("debug", config_value)
          app.console.puts("\e[90mdebug=#{display_value}\e[0m")
        end
      end
    end
  end
end
