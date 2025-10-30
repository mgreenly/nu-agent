# frozen_string_literal: true

require "spec_helper"
require "nu/agent/persona_manager"

RSpec.describe Nu::Agent::PersonaManager do
  let(:connection) { double("connection") }
  let(:manager) { described_class.new(connection) }

  describe "#list" do
    it "returns an array of all personas" do
      result = double("result")
      now = Time.now
      allow(connection).to receive(:query).and_return(result)
      allow(result).to receive(:to_a).and_return([
                                                   [1, "default", "Default prompt", true, now, now],
                                                   [2, "developer", "Developer prompt", false, now, now]
                                                 ])

      personas = manager.list

      expect(personas).to be_an(Array)
      expect(personas.size).to eq(2)
      expect(personas.first["name"]).to eq("default")
      expect(personas.last["name"]).to eq("developer")
    end

    it "returns empty array when no personas exist" do
      result = double("result")
      allow(connection).to receive(:query).and_return(result)
      allow(result).to receive(:to_a).and_return([])

      personas = manager.list

      expect(personas).to eq([])
    end
  end

  describe "#get" do
    context "when persona exists" do
      it "returns persona hash" do
        result = double("result")
        now = Time.now
        persona_data = [1, "default", "Default prompt", true, now, now]
        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([persona_data])

        persona = manager.get("default")

        expect(persona).to be_a(Hash)
        expect(persona["name"]).to eq("default")
        expect(persona["system_prompt"]).to eq("Default prompt")
      end
    end

    context "when persona does not exist" do
      it "returns nil" do
        result = double("result")
        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([])

        persona = manager.get("nonexistent")

        expect(persona).to be_nil
      end
    end
  end

  describe "#create" do
    context "with valid parameters" do
      it "creates a new persona and returns it" do
        result = double("result")
        now = Time.now
        persona_data = [10, "my-persona", "My custom prompt", false, now, now]

        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([persona_data])

        persona = manager.create(name: "my-persona", system_prompt: "My custom prompt")

        expect(persona).to be_a(Hash)
        expect(persona["name"]).to eq("my-persona")
        expect(persona["system_prompt"]).to eq("My custom prompt")
      end
    end

    context "with invalid name (contains uppercase)" do
      it "raises an error" do
        expect do
          manager.create(name: "MyPersona", system_prompt: "Prompt")
        end.to raise_error(Nu::Agent::Error, /Invalid persona name/)
      end
    end

    context "with invalid name (contains spaces)" do
      it "raises an error" do
        expect do
          manager.create(name: "my persona", system_prompt: "Prompt")
        end.to raise_error(Nu::Agent::Error, /Invalid persona name/)
      end
    end

    context "with invalid name (contains special characters)" do
      it "raises an error" do
        expect do
          manager.create(name: "my@persona", system_prompt: "Prompt")
        end.to raise_error(Nu::Agent::Error, /Invalid persona name/)
      end
    end

    context "with invalid name (exceeds 50 characters)" do
      it "raises an error" do
        long_name = "a" * 51
        expect do
          manager.create(name: long_name, system_prompt: "Prompt")
        end.to raise_error(Nu::Agent::Error, /Invalid persona name/)
      end
    end

    context "with duplicate name" do
      it "raises an error" do
        allow(connection).to receive(:query).and_raise(
          DuckDB::Error.new("Constraint Error: Duplicate key")
        )

        expect do
          manager.create(name: "default", system_prompt: "Prompt")
        end.to raise_error(Nu::Agent::Error, /already exists/)
      end
    end

    context "with empty name" do
      it "raises an error" do
        expect do
          manager.create(name: "", system_prompt: "Prompt")
        end.to raise_error(Nu::Agent::Error, /Invalid persona name/)
      end
    end

    context "with empty system_prompt" do
      it "raises an error" do
        expect do
          manager.create(name: "valid-name", system_prompt: "")
        end.to raise_error(Nu::Agent::Error, /System prompt cannot be empty/)
      end
    end
  end

  describe "#update" do
    context "when persona exists" do
      it "updates the persona and returns it" do
        result = double("result")
        now = Time.now
        existing_persona = [1, "developer", "Old prompt", false, now, now]
        updated_persona = [1, "developer", "Updated prompt", false, now, now]

        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([existing_persona], [updated_persona])

        persona = manager.update(name: "developer", system_prompt: "Updated prompt")

        expect(persona["system_prompt"]).to eq("Updated prompt")
      end
    end

    context "when persona does not exist" do
      it "raises an error" do
        result = double("result")
        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([])

        expect do
          manager.update(name: "nonexistent", system_prompt: "New prompt")
        end.to raise_error(Nu::Agent::Error, /Persona .* not found/)
      end
    end

    context "with empty system_prompt" do
      it "raises an error" do
        expect do
          manager.update(name: "developer", system_prompt: "")
        end.to raise_error(Nu::Agent::Error, /System prompt cannot be empty/)
      end
    end
  end

  describe "#delete" do
    context "when persona exists and is not default or active" do
      it "deletes the persona and returns true" do
        result = double("result")
        now = Time.now
        persona_data = [10, "custom", "Custom prompt", false, now, now]
        active_config = ["1"]
        active_persona_data = [1, "default", "Default prompt", true, now, now]

        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([persona_data], [active_config], [active_persona_data])

        result_value = manager.delete("custom")

        expect(result_value).to be(true)
      end
    end

    context "when trying to delete default persona" do
      it "raises an error" do
        result = double("result")
        now = Time.now
        persona_data = [1, "default", "Default prompt", true, now, now]

        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([persona_data])

        expect do
          manager.delete("default")
        end.to raise_error(Nu::Agent::Error, /Cannot delete the default persona/)
      end
    end

    context "when trying to delete active persona" do
      it "raises an error" do
        result = double("result")
        now = Time.now
        persona_data = [2, "developer", "Developer prompt", false, now, now]
        active_config = ["2"]

        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([persona_data], [active_config], [persona_data])

        expect do
          manager.delete("developer")
        end.to raise_error(Nu::Agent::Error, /Cannot delete the currently active persona/)
      end
    end

    context "when persona does not exist" do
      it "raises an error" do
        result = double("result")
        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([])

        expect do
          manager.delete("nonexistent")
        end.to raise_error(Nu::Agent::Error, /Persona .* not found/)
      end
    end
  end

  describe "#get_active" do
    it "returns the active persona" do
      result = double("result")
      now = Time.now
      active_config = ["1"]
      persona_data = [1, "default", "Default prompt", true, now, now]

      allow(connection).to receive(:query).and_return(result)
      allow(result).to receive(:to_a).and_return([active_config], [persona_data])

      persona = manager.get_active

      expect(persona).to be_a(Hash)
      expect(persona["name"]).to eq("default")
    end

    context "when no active persona is set" do
      it "returns the default persona" do
        result = double("result")
        now = Time.now
        persona_data = [1, "default", "Default prompt", true, now, now]

        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([], [persona_data])

        persona = manager.get_active

        expect(persona["name"]).to eq("default")
      end
    end
  end

  describe "#set_active" do
    context "when persona exists" do
      it "sets the persona as active and returns it" do
        result = double("result")
        now = Time.now
        persona_data = [2, "developer", "Developer prompt", false, now, now]

        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([persona_data])

        persona = manager.set_active("developer")

        expect(persona["name"]).to eq("developer")
      end
    end

    context "when persona does not exist" do
      it "raises an error" do
        result = double("result")
        allow(connection).to receive(:query).and_return(result)
        allow(result).to receive(:to_a).and_return([])

        expect do
          manager.set_active("nonexistent")
        end.to raise_error(Nu::Agent::Error, /Persona .* not found/)
      end
    end
  end

  describe "#validate_name" do
    it "accepts valid lowercase names" do
      expect { manager.send(:validate_name, "developer") }.not_to raise_error
    end

    it "accepts names with numbers" do
      expect { manager.send(:validate_name, "dev123") }.not_to raise_error
    end

    it "accepts names with hyphens" do
      expect { manager.send(:validate_name, "my-persona") }.not_to raise_error
    end

    it "accepts names with underscores" do
      expect { manager.send(:validate_name, "my_persona") }.not_to raise_error
    end

    it "rejects names with uppercase letters" do
      expect do
        manager.send(:validate_name, "MyPersona")
      end.to raise_error(Nu::Agent::Error, /Invalid persona name/)
    end

    it "rejects names with spaces" do
      expect do
        manager.send(:validate_name, "my persona")
      end.to raise_error(Nu::Agent::Error, /Invalid persona name/)
    end

    it "rejects names with special characters" do
      expect do
        manager.send(:validate_name, "my@persona")
      end.to raise_error(Nu::Agent::Error, /Invalid persona name/)
    end

    it "rejects names longer than 50 characters" do
      expect do
        manager.send(:validate_name, "a" * 51)
      end.to raise_error(Nu::Agent::Error, /Invalid persona name/)
    end

    it "rejects empty names" do
      expect do
        manager.send(:validate_name, "")
      end.to raise_error(Nu::Agent::Error, /Invalid persona name/)
    end
  end
end
