# Test Performance Improvement Plan

## Problem Statement

Current test suite runs slowly (~75-90 seconds for 2138 tests) because each test that uses the database:
1. Deletes the test database file
2. Creates a new `History` instance
3. Triggers `setup_schema` to create all tables
4. Runs `run_pending_migrations` to apply all migrations
5. Closes and deletes the database again

This "recreate from scratch" approach is repeated for every test, causing significant overhead.

## Proposed Solution

Implement a "**schema once, truncate between**" strategy:
- Create database schema **once** at test suite startup
- **Truncate** tables between individual tests (fast)
- Reuse the same database connection/file
- Maintain test isolation through proper cleanup

## Implementation Phases

### Phase 1: Create Test Database Helper

**Goal:** Centralize test database setup and provide truncation utilities.

- [ ] Create `spec/support/database_helper.rb` module
  - Provides `setup_test_database` method (creates schema once)
  - Provides `truncate_all_tables` method (fast cleanup between tests)
  - Provides `get_test_history` method (returns configured History instance)
  - Handles in-memory vs file-based database configuration
- [ ] Add configuration for test database mode (in-memory vs file-based)
- [ ] Implement table truncation using DuckDB's `DELETE FROM` statements
- [ ] Add logic to preserve `schema_version` table during truncation

### Phase 2: Update spec_helper.rb

**Goal:** Configure RSpec to use the new database strategy.

- [ ] Add `require 'support/database_helper'` to spec_helper.rb
- [ ] Configure `before(:suite)` hook to:
  - Create test database once
  - Run schema setup and migrations once
- [ ] Configure `before(:each)` hook to truncate tables (except schema_version)
- [ ] Configure `after(:suite)` hook to clean up test database
- [ ] Document the new test database lifecycle

### Phase 3: Refactor Existing Specs

**Goal:** Update specs to use the shared database helper.

- [ ] Update `spec/nu/agent/history_spec.rb`:
  - Remove `before`/`after` blocks that delete database
  - Use shared database helper
  - Verify test isolation works correctly
- [ ] Update other specs that create History instances:
  - `spec/nu/agent/application_console_integration_spec.rb`
  - `spec/nu/agent/exchange_migration_runner_spec.rb`
  - `spec/nu/agent/formatter_spec.rb`
- [ ] Create pattern for specs that need a clean database:
  - Most specs use truncation (fast)
  - Specific migration tests can recreate database if needed

### Phase 4: Add In-Memory Database Option

**Goal:** Enable fast in-memory database for tests that don't need persistence.

- [ ] Add configuration option for in-memory database (`:memory:`)
- [ ] Handle connection reuse for in-memory databases
- [ ] Document trade-offs (speed vs debuggability)
- [ ] Benchmark performance improvement

### Phase 5: Optimization and Edge Cases

**Goal:** Handle special cases and optimize further.

- [ ] Identify tests that require migration testing
  - These may need isolated database instances
  - Create separate helper for migration tests
- [ ] Add support for parallel test execution (if needed)
  - Use separate database files per process
  - Pattern: `db/test_#{Process.pid}.db`
- [ ] Optimize truncation order (handle any foreign key constraints)
- [ ] Add benchmarking to track test suite speed improvements

### Phase 6: Documentation and Manual Validation

**Goal:** Document new patterns and validate everything works.

- [ ] Update documentation on test database setup
- [ ] Add examples of common test patterns:
  - Tests that need database
  - Tests that need clean slate
  - Migration-specific tests
- [ ] Create troubleshooting guide for test isolation issues
- [ ] **Manual validation:**
  - Run full test suite multiple times to ensure consistency
  - Verify no test pollution between specs
  - Confirm migrations still work correctly
  - Measure and document performance improvements (target: <30 seconds)
  - Test with both in-memory and file-based configurations

## Expected Outcomes

- **Speed improvement:** 2-3x faster (target: ~30-40 seconds vs current ~75-90 seconds)
- **Better test isolation:** Explicit truncation strategy
- **Easier debugging:** Option to use file-based database to inspect state
- **Scalability:** Foundation for parallel test execution

## Technical Notes

### Current Architecture
- Custom migration system (not ActiveRecord)
- DuckDB as the database (supports fast DELETE FROM)
- Each test currently creates isolated database file
- `History.new` triggers schema setup + migrations

### Key Design Decisions
- **Truncation over transactions:** DuckDB transactions don't provide the same test isolation as PostgreSQL due to connection handling
- **Preserve schema_version:** Skip truncating this table to avoid re-running migrations
- **Configurable approach:** Support both in-memory and file-based for different use cases
- **Backward compatible:** Migration tests can still create isolated databases when needed

### Performance Considerations
- Schema setup + migrations: ~0.1-0.5s overhead per test currently
- Truncation: ~0.001-0.01s per test (100x faster)
- In-memory database: Even faster, but harder to debug
- File-based database: Slightly slower but inspectable

## Alternatives Considered

1. **Database transactions with rollback:** Not ideal for DuckDB's connection model
2. **Database cleaner gem:** Possible but adds dependency; manual approach is simpler
3. **Parallel tests:** Deferred to Phase 5, requires process-isolated databases
