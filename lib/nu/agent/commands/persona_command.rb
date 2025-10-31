# frozen_string_literal: true

require_relative "../persona_manager"
require_relative "../persona_editor"

module Nu
  module Agent
    module Commands
      # Command for managing agent personas
      class PersonaCommand < BaseCommand
        def execute(input)
          initialize_managers
          args = input.split[1..]
          command_name = input.split.first

          # If invoked as /personas with no args, show list
          return :continue if handle_personas_alias?(command_name, args)

          # Determine subcommand
          subcommand = args.first&.downcase

          case subcommand
          when nil, "help"
            show_general_help
          when "list"
            show_persona_list
          when "create"
            create_persona(args[1])
          else
            handle_persona_action(subcommand, args[1]&.downcase)
          end

          :continue
        rescue Error => e
          app.console.puts("\e[31m#{e.message}\e[0m")
          :continue
        rescue StandardError => e
          app.console.puts("\e[31mError: #{e.message}\e[0m")
          :continue
        end

        private

        def initialize_managers
          @persona_manager = PersonaManager.new(app.history.connection)
          @persona_editor = PersonaEditor.new
        end

        def handle_personas_alias?(command_name, args)
          return false unless command_name == "/personas" && args.empty?

          show_persona_list
          true
        end

        def show_general_help
          help_lines = [
            "Available commands:",
            "  /persona                    - Show this help",
            "  /persona help               - Show this help",
            "  /persona list               - List all personas with active marked",
            "  /persona create <name>      - Create new persona (opens editor)",
            "  /persona <name>             - Switch to named persona",
            "  /persona <name> show        - Display persona's system prompt",
            "  /persona <name> edit        - Edit persona in editor",
            "  /persona <name> delete      - Delete persona (with validations)"
          ]
          help_lines.each { |line| app.console.puts("\e[90m#{line}\e[0m") }
        end

        def show_persona_list
          personas = @persona_manager.list
          active_persona = @persona_manager.get_active

          app.console.puts("\e[90mAvailable personas (* = active):\e[0m")

          personas.each do |persona|
            marker = active_persona && active_persona["id"] == persona["id"] ? "*" : " "
            app.console.puts("\e[90m  #{marker} #{persona['name']}\e[0m")
          end
        end

        def handle_persona_action(persona_name, action)
          if action.nil?
            # No action means switch to persona (set_active will handle if it doesn't exist)
            switch_persona(persona_name)
          else
            # For actions, check if persona exists first
            persona = @persona_manager.get(persona_name)

            unless persona
              app.console.puts("\e[31mPersona '#{persona_name}' not found\e[0m")
              return
            end

            # Execute action on persona
            case action
            when "show"
              show_persona(persona_name)
            when "edit"
              edit_persona(persona_name)
            when "delete"
              delete_persona(persona_name)
            else
              app.console.puts("\e[31mInvalid action '#{action}' for persona '#{persona_name}'\e[0m")
              app.console.puts("\e[90mValid actions: show, edit, delete\e[0m")
            end
          end
        end

        def show_persona(name)
          persona = @persona_manager.get(name)

          app.console.puts("\e[90mPersona: #{persona['name']}\e[0m")
          app.console.puts("\e[90mSystem Prompt:\e[0m")
          app.console.puts("\e[90m#{'-' * 60}\e[0m")
          app.console.puts("\e[90m#{persona['system_prompt']}\e[0m")
          app.console.puts("\e[90m#{'-' * 60}\e[0m")
        end

        def delete_persona(name)
          @persona_manager.delete(name)
          app.console.puts("\e[90mPersona '#{name}' deleted successfully.\e[0m")
        end

        def switch_persona(name)
          persona = @persona_manager.set_active(name)

          app.console.puts("\e[90mSwitched to persona: #{persona['name']}\e[0m")
          app.console.puts("\e[90mNote: This will apply to your next conversation.\e[0m")
        end

        def create_persona(name)
          return show_usage("create") unless name

          # Check if persona already exists
          existing = @persona_manager.get(name)
          if existing
            app.console.puts("\e[31mPersona '#{name}' already exists. Use '/persona #{name} edit' to modify it.\e[0m")
            return
          end

          # Get template from default persona
          default_persona = @persona_manager.get("default")
          template = default_persona ? default_persona["system_prompt"] : ""

          # Open editor
          app.console.puts("\e[90mOpening editor to create persona '#{name}'...\e[0m")
          content = @persona_editor.edit_in_editor(initial_content: template, persona_name: name)

          if content
            @persona_manager.create(name: name, system_prompt: content)
            app.console.puts("\e[90mPersona '#{name}' created successfully.\e[0m")
          else
            app.console.puts("\e[90mPersona creation cancelled (empty content).\e[0m")
          end
        rescue PersonaEditor::EditorError => e
          app.console.puts("\e[31mEditor error: #{e.message}\e[0m")
        end

        def edit_persona(name)
          # Get persona (already checked in handle_persona_action)
          persona = @persona_manager.get(name)

          # Open editor with existing content
          app.console.puts("\e[90mOpening editor to edit persona '#{name}'...\e[0m")
          content = @persona_editor.edit_in_editor(
            initial_content: persona["system_prompt"],
            persona_name: name
          )

          if content
            @persona_manager.update(name: name, system_prompt: content)
            app.console.puts("\e[90mPersona '#{name}' updated successfully.\e[0m")
          else
            app.console.puts("\e[90mPersona edit cancelled (empty content).\e[0m")
          end
        rescue PersonaEditor::EditorError => e
          app.console.puts("\e[31mEditor error: #{e.message}\e[0m")
        end

        def show_usage(subcommand)
          app.console.puts("\e[31mUsage: /persona #{subcommand} <name>\e[0m")
        end
      end
    end
  end
end
