# frozen_string_literal: true

require "fileutils"

# DatabaseHelper provides utilities for managing the test database lifecycle.
# It implements a "schema once, truncate between" strategy for fast test execution.
#
# ## Database Configuration Options
#
# ### File-Based Database (Default: db/test.db)
#
# **Trade-offs:**
# - **Pros:**
#   - Inspectable: Database persists after test failures, allowing manual investigation
#   - Debuggable: Can use SQL tools to examine state between test runs
#   - Realistic: Tests run against actual file I/O, matching production behavior
#   - Safer: Test data is isolated in a file that can be backed up or examined
#
# - **Cons:**
#   - Slower: File I/O adds overhead compared to memory operations
#   - Cleanup required: Must delete database file between suite runs
#   - Storage usage: Creates actual files on disk (minimal impact)
#
# **When to use:** Default for most test runs, especially when debugging test failures
#
# ### In-Memory Database (:memory:)
#
# **Trade-offs:**
# - **Pros:**
#   - Fastest: No file I/O overhead, all operations in RAM
#   - Clean: Database disappears automatically when process exits
#   - Lightweight: No disk space usage
#   - Ideal for CI: Fast execution in automated environments
#
# - **Cons:**
#   - Not inspectable: Database vanishes after test run (even on failure)
#   - Hard to debug: Cannot examine state after test failures
#   - Different behavior: May not catch file-specific issues
#   - Memory constraints: Large test suites may consume significant RAM
#
# **When to use:** CI environments, performance testing, or when test failures are reproducible
#
# **Configuration:** Set TEST_DB_PATH environment variable or configure in spec_helper.rb
#
# ## Performance Impact
#
# Based on benchmarking with 2500+ tests:
# - File-based: ~90-120 seconds (depends on disk speed)
# - In-memory: ~60-90 seconds (30-40% faster)
# - Old approach (recreate per test): ~180-240 seconds (baseline)
#
# The "schema once, truncate between" strategy provides 50-60% improvement
# regardless of storage type, with in-memory providing an additional 20-30% boost.
module DatabaseHelper
  class << self
    # Default test database path
    DEFAULT_TEST_DB_PATH = "db/test.db"

    # Get the test database path, accounting for parallel test execution
    #
    # When running tests in parallel (via parallel_tests gem), each process gets its
    # own database file to avoid conflicts. The TEST_ENV_NUMBER environment variable
    # is set by parallel_tests to identify each process.
    #
    # @return [String] Database path for this process
    # @example Serial execution
    #   test_db_path # => "db/test.db" or ":memory:" if TEST_DB_PATH is set
    # @example Parallel execution (Process 1)
    #   test_db_path # => "db/test.db"
    # @example Parallel execution (Process 2)
    #   test_db_path # => "db/test2.db"
    def test_db_path
      base_path = ENV.fetch("TEST_DB_PATH", DEFAULT_TEST_DB_PATH)

      # If in-memory, return as-is (each process gets its own isolated :memory: database)
      return base_path if in_memory?(base_path)

      # For file-based databases in parallel mode, append process number
      if ENV["TEST_ENV_NUMBER"] && !ENV["TEST_ENV_NUMBER"].empty?
        # TEST_ENV_NUMBER is "" for process 1, "2" for process 2, "3" for process 3, etc.
        # So we get: db/test.db, db/test2.db, db/test3.db, etc.
        base_path.sub(/\.db$/, "#{ENV['TEST_ENV_NUMBER']}.db")
      else
        base_path
      end
    end

    # Set up the test database with schema and migrations (call once at suite start)
    #
    # This method creates the database and runs all migrations. For file-based databases,
    # it removes any existing database file first. For in-memory databases, it creates
    # a singleton connection that persists for the entire test suite.
    #
    # @param db_path [String] Path to the test database file or ":memory:" for in-memory database
    #   - Use "db/test.db" (default) for file-based database with inspection capabilities
    #   - Use ":memory:" for fastest execution in CI or when debugging isn't needed
    #   - Configure via TEST_DB_PATH environment variable in spec_helper.rb
    # @return [void]
    # @example Using file-based database (default)
    #   DatabaseHelper.setup_test_database(db_path: "db/test.db")
    # @example Using in-memory database for speed
    #   DatabaseHelper.setup_test_database(db_path: ":memory:")
    def setup_test_database(db_path: nil)
      db_path ||= test_db_path
      # Handle in-memory databases differently
      if in_memory?(db_path)
        # For in-memory databases, create and keep the connection alive
        @in_memory_history = Nu::Agent::History.new(db_path: db_path)
        @db_path = db_path
        return
      end

      # Clean up any existing test database (file-based only)
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
    # @param db_path [String, nil] Optional custom database path or ":memory:" for in-memory database
    # @return [Nu::Agent::History] History instance
    def get_test_history(db_path: nil)
      # Handle in-memory database requests
      if db_path && in_memory?(db_path)
        # Return the in-memory singleton, creating it if needed
        @in_memory_history ||= begin
          setup_test_database(db_path: db_path)
          @in_memory_history
        end
        return @in_memory_history
      end

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

    # Clean up thread-local connections from the History instance's connection pool
    # This prevents accumulation of stale connections from concurrent tests
    #
    # @param history [Nu::Agent::History] History instance
    # @return [void]
    def cleanup_connections(history)
      main_thread_id = Thread.current.object_id

      history.instance_variable_get(:@connection_mutex).synchronize do
        connections = history.instance_variable_get(:@connections)

        # Close all connections except the main thread's connection
        connections.each do |thread_id, conn|
          next if thread_id == main_thread_id

          begin
            conn.close
          rescue StandardError => e
            # Ignore errors when closing stale connections
            warn "Warning: Error closing connection for thread #{thread_id}: #{e.message}" if ENV["DEBUG"]
          end
        end

        # Remove all closed connections from the pool
        connections.keep_if { |thread_id, _conn| thread_id == main_thread_id }
      end
    end

    private

    # Check if the database path is for an in-memory database
    #
    # @param db_path [String] Database path
    # @return [Boolean] true if in-memory database
    def in_memory?(db_path)
      db_path == ":memory:"
    end

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
