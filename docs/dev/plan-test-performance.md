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

## Development Process

**Follow TDD Red → Green → Refactor cycle for each task:**
1. **RED:** Write failing test first
2. **GREEN:** Write minimal code to pass
3. **VERIFY:** Run `rake test && rake lint && rake coverage`
4. **COMMIT:** Commit the completed task
5. **UPDATE:** Update this plan's progress after each task

**Never write implementation before tests.**

## Implementation Phases

### Phase 1: Create Test Database Helper

**Goal:** Centralize test database setup and provide truncation utilities.

#### Task 1.1: Create DatabaseHelper module with setup_test_database
- [x] **RED:** Write spec for `DatabaseHelper.setup_test_database`
- [x] **GREEN:** Implement `setup_test_database` method (creates schema once)
- [x] **VERIFY:** `rake test && rake lint && rake coverage`
- [x] **COMMIT:** "Add DatabaseHelper.setup_test_database"
- [x] **UPDATE:** Mark this task complete in plan

#### Task 1.2: Add truncate_all_tables method
- [x] **RED:** Write spec for `DatabaseHelper.truncate_all_tables`
- [x] **GREEN:** Implement table truncation using DuckDB's `DELETE FROM`
- [x] **GREEN:** Add logic to preserve `schema_version` table
- [x] **VERIFY:** `rake test && rake lint && rake coverage`
- [x] **COMMIT:** "Add DatabaseHelper.truncate_all_tables"
- [x] **UPDATE:** Mark this task complete in plan (completed as part of Task 1.1)

#### Task 1.3: Add get_test_history method
- [x] **RED:** Write spec for `DatabaseHelper.get_test_history`
- [x] **GREEN:** Implement method to return configured History instance
- [x] **GREEN:** Handle in-memory vs file-based database configuration
- [x] **VERIFY:** `rake test && rake lint && rake coverage`
- [x] **COMMIT:** "Add DatabaseHelper.get_test_history with config support"
- [x] **UPDATE:** Mark this task complete in plan (completed as part of Task 1.1)

### Phase 2: Update spec_helper.rb

**Goal:** Configure RSpec to use the new database strategy.

#### Task 2.1: Add before(:suite) hook for one-time database setup
- [x] **GREEN:** Add `require 'support/database_helper'` to spec_helper.rb
- [x] **GREEN:** Configure `before(:suite)` hook to create test database once
- [x] **VERIFY:** `rake test && rake lint && rake coverage`
- [x] **COMMIT:** "Configure RSpec hooks for shared test database"
- [x] **UPDATE:** Mark this task complete in plan

#### Task 2.2: Add before(:each) hook for table truncation
- [x] **GREEN:** Configure `before(:each)` hook to truncate tables (except schema_version)
- [x] **VERIFY:** `rake test && rake lint && rake coverage`
- [x] **COMMIT:** "Configure RSpec hooks for shared test database" (combined with 2.1 and 2.3)
- [x] **UPDATE:** Mark this task complete in plan

#### Task 2.3: Add after(:suite) hook for cleanup
- [x] **GREEN:** Configure `after(:suite)` hook to clean up test database
- [x] **GREEN:** Document the new test database lifecycle in comments
- [x] **VERIFY:** `rake test && rake lint && rake coverage`
- [x] **COMMIT:** "Configure RSpec hooks for shared test database" (combined with 2.1 and 2.2)
- [x] **UPDATE:** Mark this task complete in plan

### Phase 3: Refactor Existing Specs

**Goal:** Update specs to use the shared database helper.

#### Task 3.1: Refactor history_spec.rb
- [x] **GREEN:** Remove `before`/`after` blocks that delete database in history_spec.rb
- [x] **GREEN:** Use shared database helper from DatabaseHelper module
- [x] **VERIFY:** `rake test && rake lint && rake coverage`
- [x] **VERIFY:** Confirm test isolation works correctly
- [x] **COMMIT:** "Refactor history_spec to use shared database"
- [x] **UPDATE:** Mark this task complete in plan

#### Task 3.2: Refactor application_console_integration_spec.rb
- [x] **ANALYSIS:** Spec uses mocks (`instance_double`) - no database created
- [x] **CONCLUSION:** No refactoring needed - already optimized
- [x] **UPDATE:** Mark this task complete in plan

#### Task 3.3: Refactor exchange_migration_runner_spec.rb
- [x] **ANALYSIS:** Spec uses mocks (`double`) - no database created
- [x] **CONCLUSION:** No refactoring needed - already optimized
- [x] **UPDATE:** Mark this task complete in plan

#### Task 3.4: Refactor formatter_spec.rb
- [x] **ANALYSIS:** Spec uses mocks (`instance_double`) - no database created
- [x] **CONCLUSION:** No refactoring needed - already optimized
- [x] **UPDATE:** Mark this task complete in plan

#### Task 3.5: Fix connection pool cleanup for concurrent tests
- [x] **ISSUE DISCOVERED:** Concurrent write tests failing with "Database connection closed?" errors
- [x] **ROOT CAUSE:** History connection pool accumulating stale connections from test threads
- [x] **GREEN:** Add `DatabaseHelper.cleanup_connections` method to close non-main-thread connections
- [x] **GREEN:** Add `after(:each)` hook in spec_helper.rb to call cleanup_connections
- [x] **VERIFY:** `rake test && rake lint && rake coverage` - all pass
- [x] **COMMIT:** "Fix connection pool cleanup for concurrent test isolation"
- [x] **UPDATE:** Mark this task complete in plan

### Phase 4: Add In-Memory Database Option

**Goal:** Enable fast in-memory database for tests that don't need persistence.

#### Task 4.1: Add in-memory database configuration
- [x] **RED:** Write spec for in-memory database option (`:memory:`)
- [x] **GREEN:** Implement configuration option in DatabaseHelper
- [x] **GREEN:** Handle connection reuse for in-memory databases
- [x] **VERIFY:** `rake test && rake lint && rake coverage`
- [x] **COMMIT:** "Add in-memory database configuration option"
- [x] **UPDATE:** Mark this task complete in plan

#### Task 4.2: Document and benchmark in-memory option
- [x] **GREEN:** Document trade-offs (speed vs debuggability) in comments
- [x] **GREEN:** Add benchmark code to measure performance improvement
- [x] **VERIFY:** `rake test && rake lint && rake coverage`
- [x] **COMMIT:** "Document in-memory option and add benchmarking"
- [x] **UPDATE:** Mark this task complete in plan

### Phase 5: Optimization and Edge Cases

**Goal:** Handle special cases and optimize further.

#### Task 5.1: Handle migration test isolation
- [x] **GREEN:** Identify tests that require migration testing
- [x] **GREEN:** Create separate helper pattern for migration tests with isolated DBs
- [x] **VERIFY:** `rake test && rake lint && rake coverage`
- [x] **COMMIT:** "Add isolated database pattern for migration tests"
- [x] **UPDATE:** Mark this task complete in plan

#### Task 5.2: Add parallel test execution support (optional)
- [ ] **RED:** Write spec for parallel test execution with separate DB files
- [ ] **GREEN:** Implement support using pattern `db/test_#{Process.pid}.db`
- [ ] **VERIFY:** `rake test && rake lint && rake coverage`
- [ ] **COMMIT:** "Add parallel test execution support"
- [ ] **UPDATE:** Mark this task complete in plan

#### Task 5.3: Optimize truncation and add benchmarking
- [ ] **GREEN:** Optimize truncation order (handle any foreign key constraints)
- [ ] **GREEN:** Add comprehensive benchmarking to track suite speed improvements
- [ ] **VERIFY:** `rake test && rake lint && rake coverage`
- [ ] **COMMIT:** "Optimize truncation order and enhance benchmarking"
- [ ] **UPDATE:** Mark this task complete in plan

### Phase 6: Documentation and Manual Validation

**Goal:** Document new patterns and validate everything works.

#### Task 6.1: Update test database documentation
- [ ] **GREEN:** Update documentation on test database setup
- [ ] **GREEN:** Add examples of common test patterns (database, clean slate, migrations)
- [ ] **GREEN:** Create troubleshooting guide for test isolation issues
- [ ] **VERIFY:** `rake test && rake lint && rake coverage`
- [ ] **COMMIT:** "Add comprehensive test database documentation"
- [ ] **UPDATE:** Mark this task complete in plan

#### Task 6.2: Manual Validation (HUMAN VERIFICATION REQUIRED)
- [ ] **MANUAL:** Run full test suite multiple times to ensure consistency
- [ ] **MANUAL:** Verify no test pollution between specs
- [ ] **MANUAL:** Confirm migrations still work correctly
- [ ] **MANUAL:** Measure and document actual performance improvements
  - Target: <30 seconds (vs baseline ~75-90 seconds)
  - Document actual results in this plan
- [ ] **MANUAL:** Test with both in-memory and file-based configurations
- [ ] **MANUAL:** Verify `rake test && rake lint && rake coverage` all pass consistently
- [ ] **UPDATE:** Document validation results and mark plan complete

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
