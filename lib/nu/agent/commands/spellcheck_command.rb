# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to toggle spellcheck mode
      class SpellcheckCommand < BaseCommand
        def execute(input)
          parts = input.split(" ", 2)
          if parts.length < 2 || parts[1].strip.empty?
            app.console.puts("")
            app.output_line("Usage: /spellcheck <on|off>", type: :debug)
            app.output_line("Current: spellcheck=#{app.spell_check_enabled ? 'on' : 'off'}", type: :debug)
            return :continue
          end

          setting = parts[1].strip.downcase
          if setting == "on"
            app.spell_check_enabled = true
            app.history.set_config("spell_check_enabled", "true")
            app.console.puts("")
            app.output_line("spellcheck=on", type: :debug)
          elsif setting == "off"
            app.spell_check_enabled = false
            app.history.set_config("spell_check_enabled", "false")
            app.console.puts("")
            app.output_line("spellcheck=off", type: :debug)
          else
            app.console.puts("")
            app.output_line("Invalid option. Use: /spellcheck <on|off>", type: :debug)
          end

          :continue
        end
      end
    end
  end
end
