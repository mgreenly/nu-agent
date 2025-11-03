# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::MigrationManager do
  let(:connection) { DuckDB::Database.open.connect }
  let(:schema_manager) { Nu::Agent::SchemaManager.new(connection) }
  let(:migrations_dir) { File.join(Dir.pwd, "tmp", "test_migrations") }
  let(:migration_manager) { described_class.new(connection, migrations_dir: migrations_dir) }

  before do
    schema_manager.setup_schema
  end

  after do
    connection.close
  end

  describe "#current_version" do
    it "returns 0 when schema_version table does not exist" do
      connection.query("DROP TABLE IF EXISTS schema_version")
      expect(migration_manager.current_version).to eq(0)
    end

    it "returns 0 when schema_version table is empty" do
      migration_manager.ensure_schema_version_table
      expect(migration_manager.current_version).to eq(0)
    end

    it "returns the current version from the database" do
      migration_manager.ensure_schema_version_table
      migration_manager.update_version(5)
      expect(migration_manager.current_version).to eq(5)
    end

    it "returns 0 when query fails with StandardError" do
      # Create a migration manager with a mock connection that raises an error
      mock_connection = instance_double("DuckDB::Connection")
      allow(mock_connection).to receive(:query).and_raise(StandardError, "Database error")
      error_manager = described_class.new(mock_connection, migrations_dir: migrations_dir)

      expect(error_manager.current_version).to eq(0)
    end
  end

  describe "#ensure_schema_version_table" do
    it "creates the schema_version table if it does not exist" do
      connection.query("DROP TABLE IF EXISTS schema_version")
      migration_manager.ensure_schema_version_table

      tables = connection.query("SHOW TABLES").map { |row| row[0] }
      expect(tables).to include("schema_version")
    end

    it "does not fail if table already exists" do
      migration_manager.ensure_schema_version_table
      expect { migration_manager.ensure_schema_version_table }.not_to raise_error
    end
  end

  describe "#update_version" do
    it "inserts the version into an empty table" do
      migration_manager.ensure_schema_version_table
      migration_manager.update_version(3)

      expect(migration_manager.current_version).to eq(3)
    end

    it "updates the version in the table" do
      migration_manager.ensure_schema_version_table
      migration_manager.update_version(2)
      migration_manager.update_version(5)

      expect(migration_manager.current_version).to eq(5)
    end
  end

  describe "#pending_migrations" do
    before do
      FileUtils.mkdir_p(migrations_dir)
    end

    after do
      FileUtils.rm_rf(migrations_dir)
    end

    it "returns empty array when migrations directory does not exist" do
      FileUtils.rm_rf(migrations_dir)
      expect(migration_manager.pending_migrations).to eq([])
    end

    it "returns empty array when no migration files exist" do
      expect(migration_manager.pending_migrations).to eq([])
    end

    it "returns all migrations when current version is 0" do
      File.write(File.join(migrations_dir, "001_add_user_table.rb"), "# migration")
      File.write(File.join(migrations_dir, "002_add_posts_table.rb"), "# migration")

      migrations = migration_manager.pending_migrations
      expect(migrations.map { |m| m[:version] }).to eq([1, 2])
      expect(migrations.map { |m| m[:name] }).to eq(%w[add_user_table add_posts_table])
    end

    it "returns only migrations newer than current version" do
      File.write(File.join(migrations_dir, "001_add_user_table.rb"), "# migration")
      File.write(File.join(migrations_dir, "002_add_posts_table.rb"), "# migration")
      File.write(File.join(migrations_dir, "003_add_comments_table.rb"), "# migration")

      migration_manager.ensure_schema_version_table
      migration_manager.update_version(1)

      migrations = migration_manager.pending_migrations
      expect(migrations.map { |m| m[:version] }).to eq([2, 3])
    end

    it "sorts migrations by version number" do
      File.write(File.join(migrations_dir, "003_add_comments_table.rb"), "# migration")
      File.write(File.join(migrations_dir, "001_add_user_table.rb"), "# migration")
      File.write(File.join(migrations_dir, "002_add_posts_table.rb"), "# migration")

      migrations = migration_manager.pending_migrations
      expect(migrations.map { |m| m[:version] }).to eq([1, 2, 3])
    end
  end

  describe "#run_migration" do
    it "executes the migration and updates the version" do
      migration_manager.ensure_schema_version_table

      migration = {
        version: 1,
        name: "add_test_table",
        up: lambda { |conn|
          conn.query("CREATE TABLE test_migration (id INTEGER, name TEXT)")
        }
      }

      migration_manager.run_migration(migration)

      tables = connection.query("SHOW TABLES").map { |row| row[0] }
      expect(tables).to include("test_migration")
      expect(migration_manager.current_version).to eq(1)
    end

    it "rolls back version on migration failure" do
      migration_manager.ensure_schema_version_table

      migration = {
        version: 1,
        name: "bad_migration",
        up: lambda { |_conn|
          raise "Migration failed!"
        }
      }

      expect { migration_manager.run_migration(migration) }.to raise_error(StandardError)
      expect(migration_manager.current_version).to eq(0)
    end
  end
end
