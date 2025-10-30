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
            show_usage
            return :continue
          end

          update_summarizer(parts[1].strip.downcase)
          :continue
        end

        private

        def show_usage
          app.console.puts("")
          app.output_line("Usage: /summarizer <on|off>", type: :command)
          app.output_line("Current: summarizer=#{app.summarizer_enabled ? 'on' : 'off'}", type: :command)
        end

        def update_summarizer(setting)
          case setting
          when "on"
            apply_summarizer_setting(true, "true", "on", show_reset_note: true)
          when "off"
            apply_summarizer_setting(false, "false", "off", show_reset_note: false)
          else
            app.console.puts("")
            app.output_line("Invalid option. Use: /summarizer <on|off>", type: :command)
          end
        end

        def apply_summarizer_setting(enabled, config_value, display_value, show_reset_note:)
          app.summarizer_enabled = enabled
          app.history.set_config("summarizer_enabled", config_value)
          app.console.puts("")
          app.output_line("summarizer=#{display_value}", type: :command)
          app.output_line("Summarizer will start on next /reset", type: :command) if show_reset_note
        end
      end
    end
  end
end
