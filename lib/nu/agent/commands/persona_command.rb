# frozen_string_literal: true

require_relative "../persona_manager"

module Nu
  module Agent
    module Commands
      # Command for managing agent personas
      class PersonaCommand < BaseCommand
        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def execute(input)
          args = input.split[1..] # Skip the command name

          # Initialize PersonaManager
          @persona_manager = PersonaManager.new(app.history.connection)

          # Determine subcommand
          subcommand = args.first&.downcase

          case subcommand
          when nil, "list"
            list_personas
          when "show"
            show_persona(args[1])
          when "delete"
            delete_persona(args[1])
          when "create"
            # Placeholder for Phase 4
            app.console.puts("\e[90mEditor integration for create coming in Phase 4\e[0m")
          when "edit"
            # Placeholder for Phase 4
            app.console.puts("\e[90mEditor integration for edit coming in Phase 4\e[0m")
          else
            # If there are additional arguments, treat as invalid subcommand
            if args.length > 1
              show_error("Unknown subcommand: #{subcommand}")
            else
              # Try to switch to persona by name
              switch_persona(subcommand)
            end
          end

          :continue
        rescue Error => e
          app.console.puts("\e[31m#{e.message}\e[0m")
          :continue
        rescue StandardError => e
          app.console.puts("\e[31mError: #{e.message}\e[0m")
          :continue
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        private

        def list_personas
          personas = @persona_manager.list
          active_persona = @persona_manager.get_active

          app.console.puts("\e[90mAvailable personas (* = active):\e[0m")

          personas.each do |persona|
            marker = active_persona && active_persona["id"] == persona["id"] ? "*" : " "
            app.console.puts("\e[90m  #{marker} #{persona['name']}\e[0m")
          end
        end

        def show_persona(name)
          return show_usage("show") unless name

          persona = @persona_manager.get(name)

          unless persona
            app.console.puts("\e[31mPersona '#{name}' not found\e[0m")
            return
          end

          app.console.puts("\e[90mPersona: #{persona['name']}\e[0m")
          app.console.puts("\e[90mSystem Prompt:\e[0m")
          app.console.puts("\e[90m#{'-' * 60}\e[0m")
          app.console.puts("\e[90m#{persona['system_prompt']}\e[0m")
          app.console.puts("\e[90m#{'-' * 60}\e[0m")
        end

        def delete_persona(name)
          return show_usage("delete") unless name

          @persona_manager.delete(name)
          app.console.puts("\e[90mPersona '#{name}' deleted successfully.\e[0m")
        end

        def switch_persona(name)
          persona = @persona_manager.set_active(name)

          app.console.puts("\e[90mSwitched to persona: #{persona['name']}\e[0m")
          app.console.puts("\e[90mNote: This will apply to your next conversation.\e[0m")
        end

        def show_usage(subcommand)
          app.console.puts("\e[31mUsage: /persona #{subcommand} <name>\e[0m")
        end

        def show_error(message)
          app.console.puts("\e[31m#{message}\e[0m")
          app.console.puts("\e[90mUsage: /persona [list|<name>|show <name>|" \
                           "create <name>|edit <name>|delete <name>]\e[0m")
        end
      end
    end
  end
end
