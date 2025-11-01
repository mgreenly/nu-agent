# frozen_string_literal: true

require "fileutils"

# DatabaseHelper provides utilities for managing the test database lifecycle.
# It implements a "schema once, truncate between" strategy for fast test execution.
module DatabaseHelper
  class << self
    # Default test database path
    DEFAULT_TEST_DB_PATH = "db/test.db"

    # Set up the test database with schema and migrations (call once at suite start)
    #
    # @param db_path [String] Path to the test database file
    # @return [void]
    def setup_test_database(db_path: DEFAULT_TEST_DB_PATH)
      # Clean up any existing test database
      FileUtils.rm_rf(db_path)

      # Ensure database directory exists
      FileUtils.mkdir_p(File.dirname(db_path))

      # Create new History instance which triggers schema setup and migrations
      history = Nu::Agent::History.new(db_path: db_path)

      # Close the history instance (we'll reopen it later)
      history.close

      # Store the db_path for later use
      @db_path = db_path
    end

    # Truncate all tables except schema_version (call between each test)
    #
    # @param connection [DuckDB::Connection] Database connection
    # @return [void]
    def truncate_all_tables(connection)
      # Get list of all tables using DuckDB's SHOW TABLES
      result = connection.query("SHOW TABLES")
      table_names = result.map { |row| row[0] }

      # Exclude schema_version table
      tables_to_truncate = table_names.reject do |name|
        name == "schema_version"
      end

      # Disable foreign key constraints temporarily
      connection.query("SET enable_object_cache = false")

      # Truncate tables in reverse dependency order to avoid foreign key violations
      # Child tables (with foreign keys) should be deleted before parent tables
      ordered_tables = order_tables_by_dependencies(tables_to_truncate)

      ordered_tables.each do |table_name|
        connection.query("DELETE FROM #{table_name}")
      end

      # Re-enable object cache
      connection.query("SET enable_object_cache = true")

      # Commit any open transactions to ensure clean state for next test
      # DuckDB auto-starts transactions, so we need to explicitly commit
      begin
        connection.query("COMMIT")
      rescue DuckDB::Error
        # Ignore if no transaction is active
      end

      # Re-initialize critical config values that were removed by truncation
      connection.query(<<~SQL)
        INSERT OR REPLACE INTO appconfig (key, value, updated_at)
        VALUES ('active_workers', '0', CURRENT_TIMESTAMP)
      SQL
    end

    # Get or create a singleton History instance for testing
    #
    # @param db_path [String, nil] Optional custom database path
    # @return [Nu::Agent::History] History instance
    def get_test_history(db_path: nil)
      # If a custom db_path is provided, create a new instance
      if db_path
        setup_test_database(db_path: db_path) unless File.exist?(db_path)
        return Nu::Agent::History.new(db_path: db_path)
      end

      # Otherwise, return the singleton instance
      @get_test_history ||= begin
        setup_test_database unless File.exist?(@db_path || DEFAULT_TEST_DB_PATH)
        Nu::Agent::History.new(db_path: @db_path || DEFAULT_TEST_DB_PATH)
      end
    end

    private

    # Order tables by dependencies (child tables before parent tables)
    # This ensures we can delete without foreign key violations
    def order_tables_by_dependencies(tables)
      # Known dependency order for this application:
      # failed_jobs -> exchanges, conversations
      # exchanges -> conversations
      # messages -> conversations, exchanges
      # embeddings_text_embedding_3_small -> messages
      # personas -> none
      # command_history -> none
      # conversations -> none
      # appconfig -> none

      dependency_order = %w[
        embeddings_text_embedding_3_small
        failed_jobs
        messages
        exchanges
        conversations
        personas
        command_history
        appconfig
      ]

      # Sort tables according to dependency order, with unknown tables at the end
      tables.sort_by do |table|
        index = dependency_order.index(table)
        index || dependency_order.length
      end
    end
  end
end
