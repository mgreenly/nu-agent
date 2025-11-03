# frozen_string_literal: true

# Set test environment flag to silence migration output
ENV["NU_AGENT_TEST"] = "true"

# SimpleCov must be loaded before application code
require "simplecov"
require "simplecov_json_formatter"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  add_filter "/vendor/"

  # Use JSON formatter for structured output
  formatter SimpleCov::Formatter::JSONFormatter if ENV["COVERAGE_JSON"] == "true"

  # Only enforce minimum coverage when COVERAGE_ENFORCE is set
  if ENV["COVERAGE_ENFORCE"] == "true"
    # Goal: gradually increase to 100%
    minimum_coverage line: 99.96, branch: 99.27
  end
end

require "nu/agent"
require "support/database_helper"

# Helper to silence migration output during tests
def silence_migration
  original_stdout = $stdout.dup
  original_stderr = $stderr.dup

  $stdout.reopen(File.new(File::NULL, "w"))
  $stderr.reopen(File.new(File::NULL, "w"))

  yield
ensure
  $stdout.reopen(original_stdout)
  $stderr.reopen(original_stderr)
  original_stdout.close
  original_stderr.close
end

# Helper to silence a specific stream during tests
def silence_stream(stream)
  original_stream = stream.dup
  stream.reopen(File.new(File::NULL, "w"))
  yield
ensure
  stream.reopen(original_stream)
  original_stream.close
end

RSpec.configure do |config|
  # Disable parallel execution in CI or when RSPEC_PARALLEL=false
  # Locally, parallel execution is allowed for faster test runs
  if ENV["RSPEC_PARALLEL"] == "false"
    config.files_to_run = config.files_to_run.to_a
    config.order = :defined
  end

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Test Database Lifecycle Management
  # ====================================
  # Implements a "schema once, truncate between" strategy for fast test execution:
  # 1. before(:suite) - Create database schema and run migrations once
  # 2. before(:each) - Truncate all tables (except schema_version) before each test
  # 3. after(:suite) - Clean up test database file after all tests complete
  #
  # This approach provides:
  # - Fast test execution (truncate is ~100x faster than schema recreation)
  # - Test isolation (each test starts with clean tables)
  # - Consistent migrations (schema_version table is preserved)

  # Set up the test database once at the start of the test suite
  config.before(:suite) do
    DatabaseHelper.setup_test_database
  end

  # Truncate all tables before each test to ensure test isolation
  config.before do
    history = DatabaseHelper.get_test_history
    DatabaseHelper.truncate_all_tables(history.connection)
  end

  # Clean up thread-local connections after each test
  # This prevents connection pool accumulation from concurrent tests
  config.after do
    history = DatabaseHelper.get_test_history
    DatabaseHelper.cleanup_connections(history)
  end

  # Clean up the test database after all tests complete
  # In parallel mode, each process cleans up its own database file
  config.after(:suite) do
    db_path = DatabaseHelper.test_db_path

    # Skip cleanup for in-memory databases (they disappear automatically)
    next if db_path == ":memory:"

    # Clean up the database file and any DuckDB auxiliary files
    FileUtils.rm_rf(db_path)
    FileUtils.rm_f("#{db_path}.wal")
    FileUtils.rm_f("#{db_path}-shm")
  end
end
