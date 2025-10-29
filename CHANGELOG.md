# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.10.0] - 2025-10-27

### Added
- **Documentation Organization**: Created `docs/` directory structure for better organization
- **Architecture Analysis**: Comprehensive `docs/architecture-analysis.md` documenting:
  - 13 implemented patterns (REPL, Registry, Factory, Repository, Facade, Strategy, Adapter, Builder, Template Method, Extract Class, Token/Guard, Manager, Value Object)
  - Current architecture strengths and opportunities
  - Pattern recommendations (Observer/Event, State, Chain of Responsibility, Decorator, Mediator)
  - Overall maturity grade: A- (Strong, with clear path forward)
- **Future Planning**: Created `docs/plan-0.11.md` with detailed v0.11 refactoring roadmap
- **Database Design Documentation**: Added `docs/design-overview.md` documenting database schema and relationships
- **DuckDB Safety Guide**: Added `DUCKDB_SAFETY.md` with comprehensive safety improvements:
  - Explicit CHECKPOINT before close to prevent corruption
  - WAL file detection on startup for unclean shutdown detection
  - Recovery confirmation logging
  - Format helper for readable file sizes
- **Database Integrity**: Foreign key constraints at database level:
  - `exchanges.conversation_id → conversations.id` (NOT NULL)
  - `messages.conversation_id → conversations.id`
  - `messages.exchange_id → exchanges.id`
  - Migration task (`rake foreign_key_migration`) for existing databases
- **Thread Safety Improvements**:
  - `WorkerToken` class prevents double-decrement bugs through idempotent operations
  - `SpinnerState` class encapsulates scattered state variables
  - Interrupt request flag for explicit state checking
- **Development Guidelines**: Updated `AGENT.md` with TDD practices and workflow

### Changed
- **Application Class Refactored**: Reduced from 500+ lines to 287 lines (43% reduction)
- **User Experience Improvements**:
  - Database path now shown in welcome message for transparency
  - Removed Ctrl-D from quit instructions (use Ctrl-C or /exit instead)
  - Added `report_on_exception = false` to background threads for cleaner output
- **Interrupt Handling**: Refactored Ctrl-C handling for better maintainability:
  - Extracted methods to reduce complexity
  - Removed redundant spinner cleanup (handled in rescue block)
  - Consistent exception handling across all background workers
- **Code Quality**: Achieved zero RuboCop violations across 196 files
  - 42 auto-corrections applied
  - Updated `.rubocop.yml` with justified exclusions
  - Maintained through comprehensive test coverage

### Fixed
- Deadlock issue in database `close()` method
- Double-decrement bugs in worker lifecycle management
- Inconsistent exception handling in background threads

### Technical Details
- **Test Coverage**: 680 specs passing with full coverage maintained
- **Files Reorganized**:
  - Moved `design.md` to `docs/design-overview.md`
  - Created `docs/architecture-analysis.md`
  - Created `docs/plan-0.11.md`
- **Patterns Implemented**: WorkerToken (Token/Guard), SpinnerState (Value Object)
- **Database Safety**: Zero performance overhead with significant corruption risk reduction

## [0.9.0] - Previous Release

_(Earlier changelog entries to be added)_

---

[0.10.0]: https://github.com/mgreenly/nu-agent/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/mgreenly/nu-agent/releases/tag/v0.9.0
