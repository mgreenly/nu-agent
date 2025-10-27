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
            show_usage
            return :continue
          end

          update_spellcheck(parts[1].strip.downcase)
          :continue
        end

        private

        def show_usage
          app.console.puts("")
          app.output_line("Usage: /spellcheck <on|off>", type: :debug)
          app.output_line("Current: spellcheck=#{app.spell_check_enabled ? 'on' : 'off'}", type: :debug)
        end

        def update_spellcheck(setting)
          case setting
          when "on"
            apply_spellcheck_setting(true, "true", "on")
          when "off"
            apply_spellcheck_setting(false, "false", "off")
          else
            app.console.puts("")
            app.output_line("Invalid option. Use: /spellcheck <on|off>", type: :debug)
          end
        end

        def apply_spellcheck_setting(enabled, config_value, display_value)
          app.spell_check_enabled = enabled
          app.history.set_config("spell_check_enabled", config_value)
          app.console.puts("")
          app.output_line("spellcheck=#{display_value}", type: :debug)
        end
      end
    end
  end
end
