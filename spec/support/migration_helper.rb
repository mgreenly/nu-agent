# frozen_string_literal: true

require "fileutils"

# MigrationHelper provides utilities for testing database migrations in isolation.
#
# This helper ensures that migration tests:
# - Use isolated databases (not the shared test database)
# - Have proper cleanup of database connections and files
# - Follow a consistent pattern across all migration specs
#
# ## Usage
#
# ### For In-Memory Migration Tests
#
# ```ruby
# RSpec.describe "Migration 001: add_users_table" do
#   include MigrationHelper
#
#   let(:connection) { create_isolated_connection }
#   let(:migration) { eval(File.read("migrations/001_add_users_table.rb")) }
#
#   after { cleanup_isolated_connection(connection) }
#
#   it "creates users table" do
#     migration[:up].call(connection)
#     # ... test assertions
#   end
# end
# ```
#
# ### For File-Based Migration Tests (when you need to inspect the database)
#
# ```ruby
# RSpec.describe "Migration 002: add_posts_table" do
#   include MigrationHelper
#
#   let(:db_path) { "db/test_migration_002.db" }
#   let(:connection) { create_isolated_connection(db_path: db_path) }
#   let(:migration) { eval(File.read("migrations/002_add_posts_table.rb")) }
#
#   after { cleanup_isolated_connection(connection, db_path: db_path) }
#
#   it "creates posts table" do
#     migration[:up].call(connection)
#     # ... test assertions
#   end
# end
# ```
module MigrationHelper
  # Create an isolated database connection for migration testing
  #
  # @param db_path [String, nil] Path to database file, or nil for in-memory database
  # @return [DuckDB::Connection] Database connection
  #
  # @example Create in-memory database (default, fastest)
  #   connection = create_isolated_connection
  #
  # @example Create file-based database (for debugging)
  #   connection = create_isolated_connection(db_path: "db/test_migration.db")
  def create_isolated_connection(db_path: nil)
    db = if db_path
           # Create file-based database
           FileUtils.rm_rf(db_path)
           FileUtils.mkdir_p(File.dirname(db_path))
           DuckDB::Database.open(db_path)
         else
           # Create in-memory database (faster, recommended for most tests)
           DuckDB::Database.open
         end

    @migration_database = db # Store for cleanup
    db.connect
  end

  # Clean up isolated database connection and files
  #
  # @param connection [DuckDB::Connection] Connection to close
  # @param db_path [String, nil] Database file path to delete (if file-based)
  # @return [void]
  #
  # @example Clean up in-memory database
  #   cleanup_isolated_connection(connection)
  #
  # @example Clean up file-based database
  #   cleanup_isolated_connection(connection, db_path: "db/test_migration.db")
  def cleanup_isolated_connection(connection, db_path: nil)
    # Close connection if still open
    connection.close if connection && !connection.closed?

    # Close database if we have one stored
    @migration_database&.close

    # Delete database file if specified
    FileUtils.rm_rf(db_path) if db_path && File.exist?(db_path)
  rescue StandardError => e
    # Ignore cleanup errors (connection already closed, file already deleted, etc.)
    warn "Warning: Error during migration test cleanup: #{e.message}" if ENV["DEBUG"]
  end

  # Create an isolated database with schema setup (tables but no migrations)
  #
  # This is useful when testing migrations that require certain tables to already exist.
  #
  # @param db_path [String, nil] Path to database file, or nil for in-memory database
  # @return [DuckDB::Connection] Database connection with schema
  #
  # @example Create database with schema
  #   connection = create_isolated_connection_with_schema
  #   # Connection now has all tables from SchemaManager but no migrations run
  def create_isolated_connection_with_schema(db_path: nil)
    connection = create_isolated_connection(db_path: db_path)
    schema_manager = Nu::Agent::SchemaManager.new(connection)
    schema_manager.setup_schema
    connection
  end
end
