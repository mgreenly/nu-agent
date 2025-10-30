# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/persona_command"

RSpec.describe Nu::Agent::Commands::PersonaCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:persona_manager) { instance_double("Nu::Agent::PersonaManager") }
  let(:command) { described_class.new(application) }

  before do
    allow(application).to receive_messages(history: history, console: console)
    allow(history).to receive(:connection).and_return(double("connection"))
    allow(Nu::Agent::PersonaManager).to receive(:new).and_return(persona_manager)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    context "with no arguments (list personas)" do
      it "displays all personas with active marked" do
        personas = [
          { "id" => 1, "name" => "default", "is_default" => true },
          { "id" => 2, "name" => "developer", "is_default" => false },
          { "id" => 3, "name" => "writer", "is_default" => false }
        ]
        active_persona = { "id" => 2, "name" => "developer" }

        allow(persona_manager).to receive_messages(list: personas, get_active: active_persona)

        expect(console).to receive(:puts).with("\e[90mAvailable personas (* = active):\e[0m")
        expect(console).to receive(:puts).with("\e[90m    default\e[0m")
        expect(console).to receive(:puts).with("\e[90m  * developer\e[0m")
        expect(console).to receive(:puts).with("\e[90m    writer\e[0m")

        result = command.execute("/persona")
        expect(result).to eq(:continue)
      end

      it "handles case when no active persona is set" do
        personas = [
          { "id" => 1, "name" => "default", "is_default" => true }
        ]

        allow(persona_manager).to receive_messages(list: personas, get_active: nil)

        expect(console).to receive(:puts).with("\e[90mAvailable personas (* = active):\e[0m")
        expect(console).to receive(:puts).with("\e[90m    default\e[0m")

        command.execute("/persona")
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

    context "with persona name (switch)" do
      it "switches to the specified persona" do
        persona = { "id" => 2, "name" => "developer" }

        allow(persona_manager).to receive(:set_active).with("developer").and_return(persona)

        expect(console).to receive(:puts).with("\e[90mSwitched to persona: developer\e[0m")
        expect(console).to receive(:puts).with("\e[90mNote: This will apply to your next conversation.\e[0m")

        result = command.execute("/persona developer")
        expect(result).to eq(:continue)
      end

      it "shows error when persona does not exist" do
        error = Nu::Agent::Error.new("Persona 'nonexistent' not found")
        allow(persona_manager).to receive(:set_active).with("nonexistent").and_raise(error)

        expect(console).to receive(:puts).with("\e[31mPersona 'nonexistent' not found\e[0m")

        result = command.execute("/persona nonexistent")
        expect(result).to eq(:continue)
      end
    end

    context "with 'show' subcommand" do
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

        result = command.execute("/persona show developer")
        expect(result).to eq(:continue)
      end

      it "shows error when persona does not exist" do
        allow(persona_manager).to receive(:get).with("nonexistent").and_return(nil)

        expect(console).to receive(:puts).with("\e[31mPersona 'nonexistent' not found\e[0m")

        result = command.execute("/persona show nonexistent")
        expect(result).to eq(:continue)
      end

      it "shows error when no persona name provided" do
        expect(console).to receive(:puts).with("\e[31mUsage: /persona show <name>\e[0m")

        result = command.execute("/persona show")
        expect(result).to eq(:continue)
      end
    end

    context "with 'delete' subcommand" do
      it "deletes the specified persona" do
        allow(persona_manager).to receive(:delete).with("custom").and_return(true)

        expect(console).to receive(:puts).with("\e[90mPersona 'custom' deleted successfully.\e[0m")

        result = command.execute("/persona delete custom")
        expect(result).to eq(:continue)
      end

      it "shows error when trying to delete default persona" do
        allow(persona_manager).to receive(:delete).with("default")
                                                  .and_raise(Nu::Agent::Error.new("Cannot delete the default persona"))

        expect(console).to receive(:puts).with("\e[31mCannot delete the default persona\e[0m")

        result = command.execute("/persona delete default")
        expect(result).to eq(:continue)
      end

      it "shows error when trying to delete active persona" do
        error_msg = "Cannot delete the currently active persona. Switch to another persona first."
        allow(persona_manager).to receive(:delete).with("developer")
                                                  .and_raise(Nu::Agent::Error.new(error_msg))

        expect(console).to receive(:puts).with("\e[31m#{error_msg}\e[0m")

        result = command.execute("/persona delete developer")
        expect(result).to eq(:continue)
      end

      it "shows error when persona does not exist" do
        allow(persona_manager).to receive(:delete).with("nonexistent")
                                                  .and_raise(Nu::Agent::Error.new("Persona 'nonexistent' not found"))

        expect(console).to receive(:puts).with("\e[31mPersona 'nonexistent' not found\e[0m")

        result = command.execute("/persona delete nonexistent")
        expect(result).to eq(:continue)
      end

      it "shows error when no persona name provided" do
        expect(console).to receive(:puts).with("\e[31mUsage: /persona delete <name>\e[0m")

        result = command.execute("/persona delete")
        expect(result).to eq(:continue)
      end
    end

    context "with 'create' subcommand" do
      it "shows placeholder message for Phase 4" do
        expect(console).to receive(:puts).with("\e[90mEditor integration for create coming in Phase 4\e[0m")

        result = command.execute("/persona create my-persona")
        expect(result).to eq(:continue)
      end
    end

    context "with 'edit' subcommand" do
      it "shows placeholder message for Phase 4" do
        expect(console).to receive(:puts).with("\e[90mEditor integration for edit coming in Phase 4\e[0m")

        result = command.execute("/persona edit developer")
        expect(result).to eq(:continue)
      end
    end

    context "with invalid subcommand" do
      it "shows error message" do
        expect(console).to receive(:puts).with("\e[31mUnknown subcommand: invalid\e[0m")
        expect(console).to receive(:puts).with("\e[90mUsage: /persona [list|<name>|show <name>|" \
                                               "create <name>|edit <name>|delete <name>]\e[0m")

        result = command.execute("/persona invalid arg")
        expect(result).to eq(:continue)
      end
    end

    context "command parsing" do
      it "handles extra whitespace" do
        persona = { "id" => 2, "name" => "developer" }
        allow(persona_manager).to receive(:set_active).with("developer").and_return(persona)
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

        result = command.execute("/persona")
        expect(result).to eq(:continue)
      end
    end
  end
end
