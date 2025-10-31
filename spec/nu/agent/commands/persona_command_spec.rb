# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/persona_command"

RSpec.describe Nu::Agent::Commands::PersonaCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:persona_manager) { instance_double("Nu::Agent::PersonaManager") }
  let(:persona_editor) { instance_double("Nu::Agent::PersonaEditor") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(history: history, console: console)
    allow(history).to receive(:connection).and_return(double("connection"))
    allow(Nu::Agent::PersonaManager).to receive(:new).and_return(persona_manager)
    allow(Nu::Agent::PersonaEditor).to receive(:new).and_return(persona_editor)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    context "with no arguments (show help)" do
      it "displays help text for persona command" do
        expect(console).to receive(:puts).with("\e[90mAvailable commands:\e[0m")
        expect(console).to receive(:puts).with("\e[90m  /persona                    - Show this help\e[0m")
        expect(console).to receive(:puts).with("\e[90m  /persona help               - Show this help\e[0m")
        expect(console).to receive(:puts).with(
          "\e[90m  /persona list               - List all personas with active marked\e[0m"
        )
        expect(console).to receive(:puts).with(
          "\e[90m  /persona create <name>      - Create new persona (opens editor)\e[0m"
        )
        expect(console).to receive(:puts).with("\e[90m  /persona <name>             - Switch to named persona\e[0m")
        expect(console).to receive(:puts).with(
          "\e[90m  /persona <name> show        - Display persona's system prompt\e[0m"
        )
        expect(console).to receive(:puts).with("\e[90m  /persona <name> edit        - Edit persona in editor\e[0m")
        expect(console).to receive(:puts).with(
          "\e[90m  /persona <name> delete      - Delete persona (with validations)\e[0m"
        )

        result = command.execute("/persona")
        expect(result).to eq(:continue)
      end
    end

    context "with 'help' argument" do
      it "displays help text (same as no args)" do
        expect(console).to receive(:puts).with("\e[90mAvailable commands:\e[0m")
        expect(console).to receive(:puts).with("\e[90m  /persona                    - Show this help\e[0m")
        expect(console).to receive(:puts).with("\e[90m  /persona help               - Show this help\e[0m")
        expect(console).to receive(:puts).with(
          "\e[90m  /persona list               - List all personas with active marked\e[0m"
        )
        expect(console).to receive(:puts).with(
          "\e[90m  /persona create <name>      - Create new persona (opens editor)\e[0m"
        )
        expect(console).to receive(:puts).with("\e[90m  /persona <name>             - Switch to named persona\e[0m")
        expect(console).to receive(:puts).with(
          "\e[90m  /persona <name> show        - Display persona's system prompt\e[0m"
        )
        expect(console).to receive(:puts).with("\e[90m  /persona <name> edit        - Edit persona in editor\e[0m")
        expect(console).to receive(:puts).with(
          "\e[90m  /persona <name> delete      - Delete persona (with validations)\e[0m"
        )

        result = command.execute("/persona help")
        expect(result).to eq(:continue)
      end
    end

    context "with 'list' argument" do
      it "displays all personas (same as no args)" do
        personas = [{ "id" => 1, "name" => "default", "is_default" => true }]
        active_persona = { "id" => 1, "name" => "default" }

        allow(persona_manager).to receive_messages(list: personas, get_active: active_persona)

        expect(console).to receive(:puts).with("\e[90mAvailable personas (* = active):\e[0m")
        expect(console).to receive(:puts).with("\e[90m  * default\e[0m")

        result = command.execute("/persona list")
        expect(result).to eq(:continue)
      end
    end

    context "when invoked as /personas (alias)" do
      it "lists all personas directly without arguments" do
        personas = [
          { "id" => 1, "name" => "default", "is_default" => true },
          { "id" => 2, "name" => "developer", "is_default" => false }
        ]
        active_persona = { "id" => 1, "name" => "default" }

        allow(persona_manager).to receive_messages(list: personas, get_active: active_persona)

        expect(console).to receive(:puts).with("\e[90mAvailable personas (* = active):\e[0m")
        expect(console).to receive(:puts).with("\e[90m  * default\e[0m")
        expect(console).to receive(:puts).with("\e[90m    developer\e[0m")

        result = command.execute("/personas")
        expect(result).to eq(:continue)
      end
    end

    context "with persona name (switch)" do
      it "switches to the specified persona" do
        persona = { "id" => 2, "name" => "developer" }

        allow(persona_manager).to receive(:get).with("developer").and_return(persona)
        allow(persona_manager).to receive(:set_active).with("developer").and_return(persona)
        allow(application).to receive(:reload_active_persona)

        expect(console).to receive(:puts).with("\e[90mSwitched to persona: developer\e[0m")
        expect(console).to receive(:puts).with("\e[90mNote: This will apply to your next conversation.\e[0m")

        result = command.execute("/persona developer")
        expect(result).to eq(:continue)
      end

      it "reloads active persona in application after switching" do
        persona = { "id" => 2, "name" => "developer", "system_prompt" => "Developer prompt" }

        allow(persona_manager).to receive(:get).with("developer").and_return(persona)
        allow(persona_manager).to receive(:set_active).with("developer").and_return(persona)
        allow(console).to receive(:puts)

        expect(application).to receive(:reload_active_persona).once

        command.execute("/persona developer")
      end

      it "shows error when persona does not exist" do
        error = Nu::Agent::Error.new("Persona 'nonexistent' not found")
        allow(persona_manager).to receive(:set_active).with("nonexistent").and_raise(error)

        expect(console).to receive(:puts).with("\e[31mPersona 'nonexistent' not found\e[0m")

        result = command.execute("/persona nonexistent")
        expect(result).to eq(:continue)
      end
    end

    context "with 'show' subcommand (persona name first)" do
      it "displays the persona's system prompt" do
        persona = {
          "id" => 1,
          "name" => "developer",
          "system_prompt" => "You are a focused software development assistant."
        }

        allow(persona_manager).to receive(:get).with("developer").and_return(persona)

        expect(console).to receive(:puts).with("\e[90mPersona: developer\e[0m")
        expect(console).to receive(:puts).with("\e[90mSystem Prompt:\e[0m")
        expect(console).to receive(:puts).with("\e[90m#{'-' * 60}\e[0m")
        expect(console).to receive(:puts).with("\e[90mYou are a focused software development assistant.\e[0m")
        expect(console).to receive(:puts).with("\e[90m#{'-' * 60}\e[0m")

        result = command.execute("/persona developer show")
        expect(result).to eq(:continue)
      end

      it "shows error when persona does not exist" do
        allow(persona_manager).to receive(:get).with("nonexistent").and_return(nil)

        expect(console).to receive(:puts).with("\e[31mPersona 'nonexistent' not found\e[0m")

        result = command.execute("/persona nonexistent show")
        expect(result).to eq(:continue)
      end
    end

    context "with 'delete' subcommand (persona name first)" do
      it "deletes the specified persona" do
        allow(persona_manager).to receive(:get).with("custom").and_return({ "id" => 5, "name" => "custom" })
        allow(persona_manager).to receive(:delete).with("custom").and_return(true)

        expect(console).to receive(:puts).with("\e[90mPersona 'custom' deleted successfully.\e[0m")

        result = command.execute("/persona custom delete")
        expect(result).to eq(:continue)
      end

      it "shows error when trying to delete default persona" do
        allow(persona_manager).to receive(:get).with("default").and_return({ "id" => 1, "name" => "default" })
        allow(persona_manager).to receive(:delete).with("default")
                                                  .and_raise(Nu::Agent::Error.new("Cannot delete the default persona"))

        expect(console).to receive(:puts).with("\e[31mCannot delete the default persona\e[0m")

        result = command.execute("/persona default delete")
        expect(result).to eq(:continue)
      end

      it "shows error when trying to delete active persona" do
        error_msg = "Cannot delete the currently active persona. Switch to another persona first."
        allow(persona_manager).to receive(:get).with("developer").and_return({ "id" => 2, "name" => "developer" })
        allow(persona_manager).to receive(:delete).with("developer")
                                                  .and_raise(Nu::Agent::Error.new(error_msg))

        expect(console).to receive(:puts).with("\e[31m#{error_msg}\e[0m")

        result = command.execute("/persona developer delete")
        expect(result).to eq(:continue)
      end

      it "shows error when persona does not exist" do
        allow(persona_manager).to receive(:get).with("nonexistent").and_return(nil)

        expect(console).to receive(:puts).with("\e[31mPersona 'nonexistent' not found\e[0m")

        result = command.execute("/persona nonexistent delete")
        expect(result).to eq(:continue)
      end
    end

    context "with 'create' subcommand" do
      it "opens editor and creates persona with edited content" do
        allow(persona_manager).to receive(:get).with("my-persona").and_return(nil)
        allow(persona_manager).to receive(:get).with("default").and_return({ "system_prompt" => "Default" })
        allow(persona_editor).to receive(:edit_in_editor).and_return("New persona system prompt")
        allow(persona_manager).to receive(:create).with(name: "my-persona", system_prompt: "New persona system prompt")
                                                  .and_return({ "id" => 10, "name" => "my-persona" })

        expect(console).to receive(:puts).with("\e[90mOpening editor to create persona 'my-persona'...\e[0m")
        expect(console).to receive(:puts).with("\e[90mPersona 'my-persona' created successfully.\e[0m")

        result = command.execute("/persona create my-persona")
        expect(result).to eq(:continue)
      end

      it "uses template content from default persona" do
        default_persona = { "system_prompt" => "Default prompt template" }
        allow(persona_manager).to receive(:get).with("my-persona").and_return(nil)
        allow(persona_manager).to receive(:get).with("default").and_return(default_persona)
        allow(persona_editor).to receive(:edit_in_editor).with(
          initial_content: "Default prompt template",
          persona_name: "my-persona"
        ).and_return("New content")
        allow(persona_manager).to receive(:create).and_return({ "id" => 10, "name" => "my-persona" })
        allow(console).to receive(:puts)

        command.execute("/persona create my-persona")

        expect(persona_editor).to have_received(:edit_in_editor).with(
          initial_content: "Default prompt template",
          persona_name: "my-persona"
        )
      end

      it "does not create persona when editor returns nil (cancelled)" do
        allow(persona_manager).to receive(:get).with("my-persona").and_return(nil)
        allow(persona_manager).to receive(:get).with("default").and_return({ "system_prompt" => "Default" })
        allow(persona_editor).to receive(:edit_in_editor).and_return(nil)

        expect(console).to receive(:puts).with("\e[90mOpening editor to create persona 'my-persona'...\e[0m")
        expect(console).to receive(:puts).with("\e[90mPersona creation cancelled (empty content).\e[0m")
        expect(persona_manager).not_to receive(:create)

        result = command.execute("/persona create my-persona")
        expect(result).to eq(:continue)
      end

      it "shows error when persona name already exists" do
        allow(persona_manager).to receive(:get).with("existing").and_return({ "id" => 5, "name" => "existing" })

        expect(console).to receive(:puts).with(
          "\e[31mPersona 'existing' already exists. Use '/persona existing edit' to modify it.\e[0m"
        )
        expect(persona_editor).not_to receive(:edit_in_editor)

        result = command.execute("/persona create existing")
        expect(result).to eq(:continue)
      end

      it "shows error when no persona name provided" do
        expect(console).to receive(:puts).with("\e[31mUsage: /persona create <name>\e[0m")
        expect(persona_editor).not_to receive(:edit_in_editor)

        result = command.execute("/persona create")
        expect(result).to eq(:continue)
      end

      it "handles editor errors gracefully" do
        allow(persona_manager).to receive(:get).and_return(nil)
        allow(persona_manager).to receive(:get).with("default").and_return({ "system_prompt" => "Default" })
        allow(persona_editor).to receive(:edit_in_editor)
          .and_raise(Nu::Agent::PersonaEditor::EditorError.new("Editor not found"))

        expect(console).to receive(:puts).with("\e[90mOpening editor to create persona 'my-persona'...\e[0m")
        expect(console).to receive(:puts).with("\e[31mEditor error: Editor not found\e[0m")

        result = command.execute("/persona create my-persona")
        expect(result).to eq(:continue)
      end
    end

    context "with 'edit' subcommand (persona name first)" do
      it "opens editor and updates persona with edited content" do
        existing_persona = { "id" => 2, "name" => "developer", "system_prompt" => "Original prompt" }
        active_persona = { "id" => 1, "name" => "default", "system_prompt" => "Default prompt" }
        allow(persona_manager).to receive(:get).with("developer").and_return(existing_persona)
        allow(persona_manager).to receive(:get_active).and_return(active_persona)
        allow(persona_editor).to receive(:edit_in_editor).and_return("Updated prompt")
        allow(persona_manager).to receive(:update).with(name: "developer", system_prompt: "Updated prompt")
                                                  .and_return({ "id" => 2, "name" => "developer" })

        expect(console).to receive(:puts).with("\e[90mOpening editor to edit persona 'developer'...\e[0m")
        expect(console).to receive(:puts).with("\e[90mPersona 'developer' updated successfully.\e[0m")

        result = command.execute("/persona developer edit")
        expect(result).to eq(:continue)
      end

      it "reloads active persona in application after editing active persona" do
        active_persona = { "id" => 2, "name" => "developer", "system_prompt" => "Original prompt" }
        allow(persona_manager).to receive(:get).with("developer").and_return(active_persona)
        allow(persona_manager).to receive(:get_active).and_return(active_persona)
        allow(persona_editor).to receive(:edit_in_editor).and_return("Updated prompt")
        allow(persona_manager).to receive(:update).with(name: "developer", system_prompt: "Updated prompt")
                                                  .and_return({ "id" => 2, "name" => "developer" })
        allow(console).to receive(:puts)

        expect(application).to receive(:reload_active_persona).once

        command.execute("/persona developer edit")
      end

      it "does not reload persona when editing inactive persona" do
        active_persona = { "id" => 1, "name" => "default", "system_prompt" => "Default prompt" }
        edit_persona = { "id" => 2, "name" => "developer", "system_prompt" => "Original prompt" }
        allow(persona_manager).to receive(:get).with("developer").and_return(edit_persona)
        allow(persona_manager).to receive(:get_active).and_return(active_persona)
        allow(persona_editor).to receive(:edit_in_editor).and_return("Updated prompt")
        allow(persona_manager).to receive(:update).with(name: "developer", system_prompt: "Updated prompt")
                                                  .and_return({ "id" => 2, "name" => "developer" })
        allow(console).to receive(:puts)

        expect(application).not_to receive(:reload_active_persona)

        command.execute("/persona developer edit")
      end

      it "uses existing prompt as initial content" do
        existing_persona = { "system_prompt" => "Existing content" }
        active_persona = { "id" => 1, "name" => "default" }
        allow(persona_manager).to receive(:get).with("developer").and_return(existing_persona)
        allow(persona_manager).to receive_messages(
          get_active: active_persona,
          update: { "id" => 2, "name" => "developer" }
        )
        allow(persona_editor).to receive(:edit_in_editor).with(
          initial_content: "Existing content",
          persona_name: "developer"
        ).and_return("Updated")
        allow(console).to receive(:puts)

        command.execute("/persona developer edit")

        expect(persona_editor).to have_received(:edit_in_editor).with(
          initial_content: "Existing content",
          persona_name: "developer"
        )
      end

      it "does not update persona when editor returns nil (cancelled)" do
        existing_persona = { "system_prompt" => "Original" }
        allow(persona_manager).to receive(:get).with("developer").and_return(existing_persona)
        allow(persona_editor).to receive(:edit_in_editor).and_return(nil)

        expect(console).to receive(:puts).with("\e[90mOpening editor to edit persona 'developer'...\e[0m")
        expect(console).to receive(:puts).with("\e[90mPersona edit cancelled (empty content).\e[0m")
        expect(persona_manager).not_to receive(:update)

        result = command.execute("/persona developer edit")
        expect(result).to eq(:continue)
      end

      it "shows error when persona does not exist" do
        allow(persona_manager).to receive(:get).with("nonexistent").and_return(nil)

        expect(console).to receive(:puts).with("\e[31mPersona 'nonexistent' not found\e[0m")
        expect(persona_editor).not_to receive(:edit_in_editor)

        result = command.execute("/persona nonexistent edit")
        expect(result).to eq(:continue)
      end

      it "handles editor errors gracefully" do
        existing_persona = { "system_prompt" => "Original" }
        allow(persona_manager).to receive(:get).with("developer").and_return(existing_persona)
        allow(persona_editor).to receive(:edit_in_editor)
          .and_raise(Nu::Agent::PersonaEditor::EditorError.new("Editor crashed"))

        expect(console).to receive(:puts).with("\e[90mOpening editor to edit persona 'developer'...\e[0m")
        expect(console).to receive(:puts).with("\e[31mEditor error: Editor crashed\e[0m")

        result = command.execute("/persona developer edit")
        expect(result).to eq(:continue)
      end
    end

    context "with invalid action for existing persona" do
      it "shows error message" do
        allow(persona_manager).to receive(:get).with("developer").and_return({ "id" => 2, "name" => "developer" })

        expect(console).to receive(:puts).with("\e[31mInvalid action 'invalid' for persona 'developer'\e[0m")
        expect(console).to receive(:puts).with("\e[90mValid actions: show, edit, delete\e[0m")

        result = command.execute("/persona developer invalid")
        expect(result).to eq(:continue)
      end
    end

    context "command parsing" do
      it "handles extra whitespace" do
        persona = { "id" => 2, "name" => "developer" }
        allow(persona_manager).to receive(:get).with("developer").and_return(persona)
        allow(persona_manager).to receive(:set_active).with("developer").and_return(persona)
        allow(application).to receive(:reload_active_persona)
        allow(console).to receive(:puts)

        result = command.execute("/persona    developer   ")
        expect(result).to eq(:continue)
      end

      it "handles tabs and mixed whitespace" do
        personas = [{ "id" => 1, "name" => "default", "is_default" => true }]
        active_persona = { "id" => 1, "name" => "default" }

        allow(persona_manager).to receive_messages(list: personas, get_active: active_persona)
        allow(console).to receive(:puts)

        result = command.execute("/persona\t\tlist\t")
        expect(result).to eq(:continue)
      end
    end

    context "error handling" do
      it "handles unexpected errors gracefully" do
        allow(persona_manager).to receive(:list).and_raise(StandardError.new("Database error"))

        expect(console).to receive(:puts).with("\e[31mError: Database error\e[0m")

        result = command.execute("/persona list")
        expect(result).to eq(:continue)
      end
    end
  end
end
