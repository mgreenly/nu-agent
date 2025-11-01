# Test Database Guide

## Overview

The nu-agent test suite uses a **"schema once, truncate between"** strategy for fast, isolated test execution. This approach creates the database schema and runs migrations once at suite startup, then truncates tables between individual tests.

### Performance Impact

Compared to the old "recreate from scratch" approach:
- **Old approach:** ~180-240 seconds (create/migrate for each test)
- **File-based database:** ~90-120 seconds (50-60% faster)
- **In-memory database:** ~60-90 seconds (70-75% faster)

## Database Configuration

### File-Based Database (Default)

**Path:** `db/test.db`

**Trade-offs:**
- ✅ Inspectable after test failures
- ✅ Can use SQL tools to examine state
- ✅ Tests match production file I/O behavior
- ❌ Slower than in-memory (file I/O overhead)

**When to use:** Default for local development, especially when debugging

### In-Memory Database

**Path:** `:memory:`

**Trade-offs:**
- ✅ Fastest execution (30-40% faster than file-based)
- ✅ Clean (automatically disappears on exit)
- ✅ Ideal for CI/CD pipelines
- ❌ Not inspectable after failures
- ❌ Harder to debug test issues

**Configuration:**
```ruby
# In spec_helper.rb or via environment variable
ENV["TEST_DB_PATH"] = ":memory:"
```

**When to use:** CI environments, quick local test runs, performance benchmarking

## How It Works

### Test Lifecycle

```
Suite Start (once):
  1. DatabaseHelper.setup_test_database
  2. Create schema (tables, indexes)
  3. Run all migrations
  4. Store database path/connection

Each Test (before):
  1. DatabaseHelper.truncate_all_tables
  2. Delete all data (except schema_version)
  3. Re-initialize critical config values
  4. DatabaseHelper.cleanup_connections (remove stale thread connections)

Each Test (during):
  1. Test runs with clean database
  2. Can create any data needed

Suite End (once):
  1. Close database connections
  2. Clean up test database file (if file-based)
```

### RSpec Configuration

The configuration is automatic via `spec/spec_helper.rb`:

```ruby
RSpec.configure do |config|
  config.before(:suite) do
    # Create database once
    DatabaseHelper.setup_test_database(db_path: ENV.fetch("TEST_DB_PATH", "db/test.db"))
  end

  config.before(:each) do
    # Truncate tables before each test
    history = DatabaseHelper.get_test_history
    DatabaseHelper.truncate_all_tables(history.connection)
  end

  config.after(:each) do
    # Clean up stale connections from test threads
    history = DatabaseHelper.get_test_history
    DatabaseHelper.cleanup_connections(history)
  end

  config.after(:suite) do
    # Cleanup after suite
    history = DatabaseHelper.get_test_history
    history&.close
    FileUtils.rm_f("db/test.db") unless ENV["KEEP_TEST_DB"]
  end
end
```

## Writing Tests

### Standard Test Pattern

Most tests use the shared database automatically:

```ruby
RSpec.describe History do
  it "stores messages correctly" do
    # Database is already set up and clean
    history = DatabaseHelper.get_test_history

    # Create test data
    conv_id = history.add_conversation(model: "gpt-4")
    history.add_message(
      conversation_id: conv_id,
      role: "user",
      content: "Hello"
    )

    # Verify
    messages = history.messages(conversation_id: conv_id)
    expect(messages.length).to eq(1)
    expect(messages.first[:content]).to eq("Hello")
  end

  # Next test starts with clean database
  it "handles multiple conversations" do
    history = DatabaseHelper.get_test_history

    # Database is clean (previous test's data is gone)
    conversations = history.conversations
    expect(conversations).to be_empty

    # Create new test data
    conv_id1 = history.add_conversation(model: "gpt-4")
    conv_id2 = history.add_conversation(model: "claude-3")

    expect(history.conversations.length).to eq(2)
  end
end
```

### Migration Test Pattern

**Migration tests need isolated databases** to test schema changes from scratch:

```ruby
RSpec.describe "Migration 007" do
  it "adds new column correctly" do
    # Create isolated database for this test
    db_path = "db/test_migration_007_#{SecureRandom.hex(4)}.db"

    begin
      # Test migration on clean database
      history = History.new(db_path: db_path)

      # Verify migration results
      result = history.connection.query("PRAGMA table_info(conversations)")
      columns = result.map { |row| row[1] }
      expect(columns).to include("new_column")

      history.close
    ensure
      # Clean up isolated database
      FileUtils.rm_f(db_path)
    end
  end
end
```

### Concurrent Test Pattern

For tests with threads or concurrent operations:

```ruby
RSpec.describe "Concurrent operations" do
  it "handles concurrent writes safely" do
    history = DatabaseHelper.get_test_history
    conv_id = history.add_conversation(model: "gpt-4")

    # Spawn threads for concurrent operations
    threads = 10.times.map do |i|
      Thread.new do
        history.add_message(
          conversation_id: conv_id,
          role: "user",
          content: "Message #{i}"
        )
      end
    end

    threads.each(&:join)

    # Verify results
    messages = history.messages(conversation_id: conv_id)
    expect(messages.length).to eq(10)
  end
end
```

**Note:** The `after(:each)` hook automatically cleans up thread-local connections via `DatabaseHelper.cleanup_connections`.

## Benchmarking

### Run Performance Tests

**Basic benchmark (5 runs):**
```bash
rake benchmark:test
```

**Custom number of runs:**
```bash
rake benchmark:test RUNS=10
```

**Output:**
```
🔬 Benchmarking test suite performance (5 runs)...
================================================================================

Run 1/5: 108.45s
Run 2/5: 107.82s
Run 3/5: 108.21s
Run 4/5: 107.95s
Run 5/5: 108.33s

================================================================================
📊 Statistics:
================================================================================
Mean:     108.15s
Median:   108.21s
Min:      107.82s
Max:      108.45s
Std Dev:  0.24s
Range:    0.63s

💡 Baseline (old approach): ~180-240s
✨ Current performance:     ~108s (48% improvement)
```

### Compare Database Types

```bash
rake benchmark:compare
```

**Output:**
```
🔬 Comparing database configurations (3 runs each)...
================================================================================

📁 File-based database (db/test.db):
  Run 1/3: 108.45s
  Run 2/3: 107.82s
  Run 3/3: 108.21s

💾 In-memory database (:memory:):
  Run 1/3: 75.23s
  Run 2/3: 74.89s
  Run 3/3: 75.15s

================================================================================
📊 Comparison:
================================================================================
File-based:  108.16s (mean)
In-memory:   75.09s (mean)
Difference:  33.07s (30.6% faster with in-memory)
```

## Troubleshooting

### Issue: Tests fail with "Database connection closed?"

**Symptoms:**
```
DuckDB::Error: Failed to extract statements(Database connection closed?).
```

**Cause:** Thread-local connections accumulating in the connection pool from concurrent tests.

**Solution:** Already handled automatically by `DatabaseHelper.cleanup_connections` in the `after(:each)` hook. If you see this error:

1. Verify `spec_helper.rb` has the `after(:each)` hook configured
2. Check that your test properly uses `DatabaseHelper.get_test_history`
3. Ensure threads are properly joined before test ends

### Issue: Test pollution between tests

**Symptoms:** Test fails when run with others, but passes when run alone.

**Cause:** Data from previous tests not being cleaned up.

**Debugging:**
```ruby
it "starts with clean database" do
  history = DatabaseHelper.get_test_history

  # Verify clean state
  expect(history.conversations).to be_empty
  expect(history.messages).to be_empty

  # Your test logic here
end
```

**Solution:**
- Verify `before(:each)` hook is calling `DatabaseHelper.truncate_all_tables`
- Check that custom `before` blocks aren't interfering
- Ensure test isn't bypassing `DatabaseHelper.get_test_history`

### Issue: Migration tests fail with "table already exists"

**Symptoms:**
```
DuckDB::Error: Table already exists: table_name
```

**Cause:** Migration test using shared database instead of isolated database.

**Solution:** Use isolated database pattern for migration tests:

```ruby
it "tests migration" do
  db_path = "db/test_migration_#{SecureRandom.hex(4)}.db"

  begin
    history = History.new(db_path: db_path)
    # Test migration logic
    history.close
  ensure
    FileUtils.rm_f(db_path)
  end
end
```

### Issue: Slow test suite

**Symptoms:** Tests taking longer than expected.

**Diagnostics:**
```bash
# Benchmark current performance
rake benchmark:test RUNS=3

# Compare configurations
rake benchmark:compare
```

**Solutions:**

1. **Use in-memory database for CI:**
   ```yaml
   # .github/workflows/test.yml
   - name: Run tests
     run: rake test
     env:
       TEST_DB_PATH: ':memory:'
   ```

2. **Check for migration tests using shared database:**
   - Migration tests should use isolated databases
   - Look for tests creating `History.new` without custom `db_path`

3. **Profile slow tests:**
   ```bash
   bundle exec rspec --profile 10
   ```

### Issue: Can't inspect database after test failure

**Symptoms:** Need to examine database state but using `:memory:`.

**Solution:** Switch to file-based database temporarily:

```bash
# Run specific test with file-based database
TEST_DB_PATH=db/test.db bundle exec rspec spec/path/to/failing_spec.rb

# Keep database after test for inspection
KEEP_TEST_DB=1 TEST_DB_PATH=db/test.db bundle exec rspec spec/path/to/failing_spec.rb

# Inspect the database
duckdb db/test.db "SELECT * FROM conversations;"
```

### Issue: Foreign key constraint errors during truncation

**Symptoms:**
```
DuckDB::Error: Foreign key constraint violation
```

**Cause:** Tables being truncated in wrong order.

**Solution:** Update dependency order in `spec/support/database_helper.rb`:

```ruby
def order_tables_by_dependencies(tables)
  # Update this array with correct dependency order
  # Child tables (with foreign keys) should come BEFORE parent tables
  dependency_order = %w[
    embeddings_text_embedding_3_small  # References messages
    failed_jobs                        # References exchanges, conversations
    messages                           # References conversations, exchanges
    exchanges                          # References conversations
    conversations                      # No dependencies
    personas
    command_history
    appconfig
  ]

  # Sort implementation...
end
```

## Best Practices

### DO ✅

- **Use `DatabaseHelper.get_test_history`** for shared database access
- **Keep tests isolated** - don't rely on data from other tests
- **Use isolated databases for migration tests**
- **Clean up threads properly** with `threads.each(&:join)`
- **Use in-memory database in CI** for faster builds
- **Benchmark performance** after making test changes

### DON'T ❌

- **Don't create database manually** - use `DatabaseHelper` methods
- **Don't skip cleanup** - always ensure threads are joined
- **Don't test migrations on shared database** - use isolated databases
- **Don't commit test database files** - they're in `.gitignore`
- **Don't rely on specific data existing** - tests may run in any order
- **Don't use `History.new` in shared tests** - use `DatabaseHelper.get_test_history`

## Advanced Topics

### Custom Database Configuration

For special test scenarios:

```ruby
RSpec.describe "Special scenario" do
  around(:each) do |example|
    # Create custom database for this test
    custom_db = "db/test_custom_#{SecureRandom.hex(4)}.db"

    begin
      history = History.new(db_path: custom_db)
      # Make history available to test
      @history = history

      example.run

      history.close
    ensure
      FileUtils.rm_f(custom_db)
    end
  end

  it "uses custom database" do
    expect(@history).to be_a(History)
    # Test logic here
  end
end
```

### Parallel Test Execution

**Note:** Parallel test execution is planned for future implementation (see GitHub issue #38).

When implemented, each parallel process will use its own database file:
```ruby
test_db_path = "db/test_#{Process.pid}.db"
```

## Related Documentation

- **Test Performance Plan:** `docs/dev/plan-test-performance.md`
- **Database Helper Implementation:** `spec/support/database_helper.rb`
- **RSpec Configuration:** `spec/spec_helper.rb`
- **Migration Documentation:** `docs/dev/migrations.md`
- **Benchmarking Tasks:** `Rakefile` (benchmark namespace)

## Questions or Issues?

If you encounter problems not covered in this guide:

1. Check the [Troubleshooting](#troubleshooting) section
2. Run benchmarks to diagnose performance issues
3. Review `spec/support/database_helper.rb` for implementation details
4. Create a GitHub issue with test output and configuration details
