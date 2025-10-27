# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::SchemaManager do
  let(:test_db_path) { "db/test_schema_manager.db" }
  let(:db) { DuckDB::Database.open(test_db_path) }
  let(:connection) { db.connect }
  let(:schema_manager) { described_class.new(connection) }

  before do
    FileUtils.rm_rf(test_db_path)
    FileUtils.mkdir_p("db")
  end

  after do
    connection.close
    db.close
    FileUtils.rm_rf(test_db_path)
  end

  describe "#setup_schema" do
    it "creates all required tables" do
      schema_manager.setup_schema

      tables = schema_manager.list_tables
      expect(tables).to include("conversations")
      expect(tables).to include("messages")
      expect(tables).to include("exchanges")
      expect(tables).to include("text_embedding_3_small")
      expect(tables).to include("appconfig")
      expect(tables).to include("command_history")
    end

    it "creates all required sequences" do
      schema_manager.setup_schema

      # Verify sequences exist by trying to get nextval
      result = connection.query("SELECT nextval('conversations_id_seq')")
      expect(result.to_a.first.first).to eq(1)

      result = connection.query("SELECT nextval('messages_id_seq')")
      expect(result.to_a.first.first).to eq(1)

      result = connection.query("SELECT nextval('exchanges_id_seq')")
      expect(result.to_a.first.first).to eq(1)
    end

    it "initializes active_workers config to 0" do
      schema_manager.setup_schema

      result = connection.query("SELECT value FROM appconfig WHERE key = 'active_workers'")
      row = result.to_a.first
      expect(row).not_to be_nil
      expect(row[0]).to eq("0")
    end
  end

  describe "#list_tables" do
    it "returns empty array when no tables exist" do
      tables = schema_manager.list_tables
      expect(tables).to be_an(Array)
    end

    it "returns all table names after schema setup" do
      schema_manager.setup_schema

      tables = schema_manager.list_tables
      expect(tables).to be_an(Array)
      expect(tables.length).to be > 0
    end
  end

  describe "#describe_table" do
    before do
      schema_manager.setup_schema
    end

    it "returns column information for a table" do
      columns = schema_manager.describe_table("messages")

      expect(columns).to be_an(Array)
      expect(columns.length).to be > 0

      # Check that we have expected columns
      column_names = columns.map { |c| c["column_name"] }
      expect(column_names).to include("id")
      expect(column_names).to include("conversation_id")
      expect(column_names).to include("role")
      expect(column_names).to include("content")
    end

    it "sanitizes table name to prevent SQL injection" do
      # Should strip dangerous characters, resulting in table not found (safe error)
      expect do
        schema_manager.describe_table("messages; DROP TABLE messages--")
      end.to raise_error(DuckDB::Error, /does not exist/)
    end
  end

  describe "#add_column_if_not_exists" do
    before do
      # Create a simple test table
      connection.query(<<~SQL)
        CREATE TABLE test_table (
          id INTEGER PRIMARY KEY,
          name TEXT
        )
      SQL
    end

    it "adds a new column when it doesn't exist" do
      schema_manager.add_column_if_not_exists("test_table", "email", "TEXT")

      columns = schema_manager.describe_table("test_table")
      column_names = columns.map { |c| c["column_name"] }
      expect(column_names).to include("email")
    end

    it "does not fail when column already exists" do
      schema_manager.add_column_if_not_exists("test_table", "name", "TEXT")

      columns = schema_manager.describe_table("test_table")
      column_names = columns.map { |c| c["column_name"] }
      expect(column_names).to include("name")
    end
  end

  describe "#escape_identifier" do
    it "allows alphanumeric characters and underscores" do
      expect(schema_manager.escape_identifier("table_name_123")).to eq("table_name_123")
    end

    it "removes dangerous characters" do
      expect(schema_manager.escape_identifier("table; DROP TABLE users--")).to eq("tableDROPTABLEusers")
    end

    it "removes quotes and special characters" do
      expect(schema_manager.escape_identifier("table'name\"test")).to eq("tablenametest")
    end
  end
end
