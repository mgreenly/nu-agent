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
            app.console.puts("\e[90mUsage: /debug <on|off>\e[0m")
            app.console.puts("\e[90mCurrent: debug=#{app.debug ? 'on' : 'off'}\e[0m")
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == "on"
            app.debug = true
            app.formatter.debug = true
            app.history.set_config("debug", "true")
            app.console.puts("\e[90mdebug=on\e[0m")
          elsif setting == "off"
            app.debug = false
            app.formatter.debug = false
            app.history.set_config("debug", "false")
            app.console.puts("\e[90mdebug=off\e[0m")
          else
            app.console.puts("\e[90mInvalid option. Use: /debug <on|off>\e[0m")
          end

          :continue
        end
      end
    end
  end
end
