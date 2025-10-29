# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::ConfigStore do
  let(:test_db_path) { "db/test_config_store.db" }
  let(:db) { DuckDB::Database.open(test_db_path) }
  let(:connection) { db.connect }
  let(:config_store) { described_class.new(connection) }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }

  before do
    FileUtils.rm_rf(test_db_path)
    FileUtils.mkdir_p("db")
    # Setup schema so tables exist
    schema_manager.setup_schema
  end

  after do
    connection.close
    db.close
    FileUtils.rm_rf(test_db_path)
  end

  describe "#set_config" do
    it "stores a configuration value" do
      config_store.set_config("debug", "true")

      result = connection.query("SELECT value FROM appconfig WHERE key = 'debug'")
      expect(result.to_a.first.first).to eq("true")
    end

    it "updates existing configuration value" do
      config_store.set_config("debug", "false")
      config_store.set_config("debug", "true")

      result = connection.query("SELECT value FROM appconfig WHERE key = 'debug'")
      expect(result.to_a.first.first).to eq("true")
    end

    it "converts values to strings" do
      config_store.set_config("count", 42)

      result = connection.query("SELECT value FROM appconfig WHERE key = 'count'")
      expect(result.to_a.first.first).to eq("42")
    end
  end

  describe "#get_config" do
    it "retrieves stored configuration value" do
      config_store.set_config("debug", "true")

      value = config_store.get_config("debug")
      expect(value).to eq("true")
    end

    it "returns default when key does not exist" do
      value = config_store.get_config("nonexistent", default: "fallback")
      expect(value).to eq("fallback")
    end

    it "returns nil when key does not exist and no default provided" do
      value = config_store.get_config("nonexistent")
      expect(value).to be_nil
    end
  end

  describe "#add_command_history" do
    it "stores a command in history" do
      config_store.add_command_history("ls -la")

      result = connection.query("SELECT command FROM command_history")
      expect(result.to_a.first.first).to eq("ls -la")
    end

    it "does not store nil commands" do
      config_store.add_command_history(nil)

      result = connection.query("SELECT COUNT(*) FROM command_history")
      expect(result.to_a.first.first).to eq(0)
    end

    it "does not store empty commands" do
      config_store.add_command_history("   ")

      result = connection.query("SELECT COUNT(*) FROM command_history")
      expect(result.to_a.first.first).to eq(0)
    end

    it "stores multiple commands" do
      config_store.add_command_history("ls")
      config_store.add_command_history("pwd")
      config_store.add_command_history("cd /tmp")

      result = connection.query("SELECT COUNT(*) FROM command_history")
      expect(result.to_a.first.first).to eq(3)
    end
  end

  describe "#get_command_history" do
    before do
      config_store.add_command_history("first command")
      config_store.add_command_history("second command")
      config_store.add_command_history("third command")
    end

    it "returns command history in chronological order (oldest first)" do
      history = config_store.get_command_history

      expect(history.length).to eq(3)
      expect(history[0]["command"]).to eq("first command")
      expect(history[1]["command"]).to eq("second command")
      expect(history[2]["command"]).to eq("third command")
    end

    it "respects limit parameter" do
      history = config_store.get_command_history(limit: 2)

      expect(history.length).to eq(2)
      expect(history[0]["command"]).to eq("second command")
      expect(history[1]["command"]).to eq("third command")
    end

    it "includes created_at timestamp" do
      history = config_store.get_command_history

      expect(history.first["created_at"]).not_to be_nil
    end
  end

  describe "#get_int" do
    it "converts string values to integers" do
      config_store.set_config("batch_size", "10")

      value = config_store.get_int("batch_size")
      expect(value).to eq(10)
      expect(value).to be_a(Integer)
    end

    it "returns default when key does not exist" do
      value = config_store.get_int("nonexistent", default: 42)
      expect(value).to eq(42)
    end

    it "returns nil when key does not exist and no default provided" do
      value = config_store.get_int("nonexistent")
      expect(value).to be_nil
    end

    it "handles negative integers" do
      config_store.set_config("offset", "-5")

      value = config_store.get_int("offset")
      expect(value).to eq(-5)
    end

    it "raises error for invalid integer strings" do
      config_store.set_config("invalid", "not_a_number")

      expect { config_store.get_int("invalid") }.to raise_error(ArgumentError)
    end
  end

  describe "#get_float" do
    it "converts string values to floats" do
      config_store.set_config("threshold", "0.75")

      value = config_store.get_float("threshold")
      expect(value).to eq(0.75)
      expect(value).to be_a(Float)
    end

    it "returns default when key does not exist" do
      value = config_store.get_float("nonexistent", default: 3.14)
      expect(value).to eq(3.14)
    end

    it "returns nil when key does not exist and no default provided" do
      value = config_store.get_float("nonexistent")
      expect(value).to be_nil
    end

    it "handles negative floats" do
      config_store.set_config("temp", "-1.5")

      value = config_store.get_float("temp")
      expect(value).to eq(-1.5)
    end

    it "raises error for invalid float strings" do
      config_store.set_config("invalid", "not_a_number")

      expect { config_store.get_float("invalid") }.to raise_error(ArgumentError)
    end
  end

  describe "#get_bool" do
    it "returns true for 'true' string" do
      config_store.set_config("enabled", "true")

      value = config_store.get_bool("enabled")
      expect(value).to be true
    end

    it "returns false for 'false' string" do
      config_store.set_config("enabled", "false")

      value = config_store.get_bool("enabled")
      expect(value).to be false
    end

    it "returns default when key does not exist" do
      value = config_store.get_bool("nonexistent", default: true)
      expect(value).to be true
    end

    it "returns nil when key does not exist and no default provided" do
      value = config_store.get_bool("nonexistent")
      expect(value).to be_nil
    end

    it "is case-insensitive" do
      config_store.set_config("flag1", "TRUE")
      config_store.set_config("flag2", "True")
      config_store.set_config("flag3", "FALSE")
      config_store.set_config("flag4", "False")

      expect(config_store.get_bool("flag1")).to be true
      expect(config_store.get_bool("flag2")).to be true
      expect(config_store.get_bool("flag3")).to be false
      expect(config_store.get_bool("flag4")).to be false
    end

    it "raises error for invalid boolean strings" do
      config_store.set_config("invalid", "yes")

      expect { config_store.get_bool("invalid") }.to raise_error(ArgumentError)
    end
  end
end
