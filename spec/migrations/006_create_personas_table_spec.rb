# frozen_string_literal: true

require "spec_helper"
require "duckdb"
require "nu/agent/persona_manager"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Migration 006: create_personas_table" do
  let(:db) { DuckDB::Database.open }
  let(:conn) { db.connect }
  let(:migration) { eval(File.read("migrations/006_create_personas_table.rb")) } # rubocop:disable Security/Eval

  before do
    # Create appconfig table (required for migration)
    conn.query(<<~SQL)
      CREATE TABLE appconfig (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    SQL
  end

  after do
    conn.disconnect
  end

  describe "migration execution" do
    it "creates personas table with 5 default personas" do
      # Run the migration
      migration[:up].call(conn)

      # Verify table exists
      result = conn.query(<<~SQL)
        SELECT COUNT(*) FROM personas
      SQL
      expect(result.to_a.first[0]).to eq(5)

      # Verify default persona exists
      result = conn.query("SELECT name FROM personas WHERE name = 'default'")
      rows = result.to_a
      expect(rows).not_to be_empty
      expect(rows.first[0]).to eq("default")
    end

    it "sets default persona as active in appconfig" do
      # Run the migration
      migration[:up].call(conn)

      # Get the default persona ID
      result = conn.query("SELECT id FROM personas WHERE name = 'default'")
      default_id = result.to_a.first[0]
      expect(default_id).not_to be_nil

      # Verify it's stored in appconfig
      result = conn.query("SELECT value FROM appconfig WHERE key = 'active_persona_id'")
      active_id = result.to_a.first[0]
      expect(active_id).to eq(default_id.to_s)
    end

    it "is idempotent (can run multiple times)" do
      # Run migration twice
      migration[:up].call(conn)

      # Running again should not fail or create duplicates
      expect do
        # Clear personas for second run
        conn.query("DELETE FROM personas")
        conn.query("DELETE FROM appconfig WHERE key = 'active_persona_id'")
        migration[:up].call(conn)
      end.not_to raise_error

      # Should still have 5 personas
      result = conn.query("SELECT COUNT(*) FROM personas")
      expect(result.to_a.first[0]).to eq(5)
    end
  end

  describe "PersonaManager integration" do
    let(:manager) { Nu::Agent::PersonaManager.new(conn) }

    before do
      # Run the migration
      migration[:up].call(conn)
    end

    it "can list all personas after migration" do
      personas = manager.list

      expect(personas).to be_an(Array)
      expect(personas.size).to eq(5)

      # Verify we can access persona attributes
      default_persona = personas.find { |p| p["name"] == "default" }
      expect(default_persona).not_to be_nil
      expect(default_persona["system_prompt"]).to include("Format all responses in raw text")
      expect(default_persona["is_default"]).to be(true)
    end

    it "can get a specific persona by name" do
      persona = manager.get("developer")

      expect(persona).not_to be_nil
      expect(persona["name"]).to eq("developer")
      expect(persona["system_prompt"]).to include("software development assistant")
      expect(persona["is_default"]).to be(false)
    end

    it "can get the active persona" do
      active_persona = manager.get_active

      expect(active_persona).not_to be_nil
      expect(active_persona["name"]).to eq("default")
      expect(active_persona["is_default"]).to be(true)
    end

    it "can switch active persona" do
      # Switch to developer
      result = manager.set_active("developer")
      expect(result["name"]).to eq("developer")

      # Verify it's now active
      active = manager.get_active
      expect(active["name"]).to eq("developer")
    end

    it "cannot delete default persona" do
      expect do
        manager.delete("default")
      end.to raise_error(Nu::Agent::Error, /Cannot delete the default persona/)
    end

    it "cannot delete active persona" do
      # Switch to developer
      manager.set_active("developer")

      # Try to delete it
      expect do
        manager.delete("developer")
      end.to raise_error(Nu::Agent::Error, /Cannot delete the currently active persona/)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
