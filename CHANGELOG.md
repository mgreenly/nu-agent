# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.11.0] - 2025-10-30

### Added

- **RAG (Retrieval-Augmented Generation) System** (Issue #17, #5): Complete conversational memory system using vector similarity search
  - **Pausable Background Tasks Infrastructure**:
    - `PausableTask` base class with pause/resume/shutdown support
    - Cooperative pause checking with max 200ms sleep blocks for responsive control
    - `pause_all/resume_all/wait_until_all_paused` methods in BackgroundWorkerManager
  - **Database Schema Migrations Framework**:
    - `SchemaManager` and `MigrationManager` for safe schema evolution
    - `schema_version` table and `migrations/` directory structure
    - Automatic pending migration application on startup
  - **DuckDB VSS Extension Support**:
    - HNSW vector similarity search index with cosine distance metric
    - Graceful fallback to linear scan when VSS extension unavailable
    - Dual-mode operation verified with comprehensive testing
  - **Exchange Summarization Worker**:
    - Generates concise LLM summaries for each completed exchange
    - Filters redacted messages from summary prompts for privacy
    - Thread-safe status tracking with graceful shutdown during LLM calls
    - Cost tracking from provider token usage
  - **Embedding Generation Worker** (formerly EmbeddingPipeline):
    - Generates embeddings for conversation and exchange summaries
    - Batch requests with configurable batch size and rate limiting
    - Exponential backoff with jitter on API errors (max 3 attempts)
    - Upsert semantics with uniqueness enforcement
  - **RAG Retrieval Pipeline** (Chain of Responsibility pattern):
    - `QueryEmbeddingProcessor`: Embed user query once per request
    - `ConversationSearchProcessor`: VSS-based top-K conversation summaries with min_similarity threshold
    - `ExchangeSearchProcessor`: Per-conversation top-M exchanges with global caps
    - `ContextFormatterProcessor`: Token-budgeted document builder (40% conversations, 60% exchanges)
    - Similarity-primary ranking with recency as tie-breaker
  - **New Commands**:
    - `/rag`: Status, on/off, test queries, configuration (limits, thresholds, budgets)
    - `/embeddings`: Renamed from old command with status, on/off, start, batch, rate, reset
  - **Database Enhancements**:
    - Foreign key constraints with ON DELETE CASCADE for embeddings
    - Uniqueness constraints: `UNIQUE(kind, conversation_id)`, `UNIQUE(kind, exchange_id)`
    - Typed config getters: `get_int/get_float/get_bool` with validation
    - Parameterized SQL throughout (eliminated string interpolation)

- **Database Backup Command** (Issue #9): Production-ready `/backup` command
  - **Core Functionality**:
    - Default timestamped backups: `./memory-YYYY-MM-DD-HHMMSS.db`
    - Custom destination path support with `~` expansion
    - Automatic worker pause/resume coordination
    - Backup verification (existence and size checks)
  - **Progress Tracking**:
    - Progress bar for files > 1 MB
    - Shows percentage, bytes copied, and total size
    - Updates every 1 MB during file copy
    - Efficient FileUtils.cp for small files
  - **Pre-flight Validation**:
    - Source database file exists and is readable
    - Destination directory exists or can be created
    - Destination directory is writable
    - Sufficient disk space available (using df command)
    - Fail-fast with clear error messages
  - **Safety Guarantees**:
    - Workers always resume even on failure (via ensure blocks)
    - Database connection management
    - Error handling with actionable messages

- **Unified Worker Command Interface**:
  - **Individual Worker Control**:
    - `/worker <name> start/stop` - Control specific workers
    - `/worker <name> enable/disable` - Enable/disable workers with config persistence
    - `/worker <name> status` - Get detailed worker status
    - `/worker status` - Show status for all workers
  - **Per-Worker Verbosity Controls**:
    - Independent verbosity settings for each worker (ConversationSummarizer, ExchangeSummarizer, EmbeddingGenerator)
    - Dynamic verbosity reloading without restart
    - Verbosity levels 0-3 for granular debug output control
  - **Worker Model Configuration**:
    - `conversation_summarizer_model` and `exchange_summarizer_model` config options
    - Fallback to general summarizer model when worker-specific model not configured
    - Per-worker model selection for cost optimization

- **Code Organization**:
  - Organized background workers into `Nu::Agent::Workers` namespace
  - Moved worker files to `lib/nu/agent/workers/` directory
  - Moved spec files to `spec/nu/agent/workers/` directory
  - Improved scalability for future worker additions

- **ConsoleIO Enhancements**:
  - Progress bar mode methods (`start_progress`, `update_progress`, `end_progress`)
  - Foundation for future real-time progress display (Issue #25)
  - Buffered progress output for backup operations

### Changed

- **Command Interface**:
  - Updated `/help` with `/worker`, `/rag`, and `/backup` documentation
  - Removed deprecated commands: `/summarizer`, `/fix`, `/index-man`
- **Worker Architecture**:
  - Refactored `ConversationSummarizer` and `ExchangeSummarizer` to inherit from `PausableTask`
  - Background workers now accept `config_store` for dynamic configuration
  - Improved worker status tracking and observability
- **Configuration System**:
  - Added typed configuration getters with validation
  - Extended `Configuration` struct with worker-specific model fields
  - Enhanced `ConfigurationLoader` to support per-worker models
- **Command Visibility**:
  - Created new `:command` output type that always displays (gray styling)
  - Changed 108 instances from `type: :debug` to `type: :command` across command files
  - Commands now visible without debug mode enabled

### Fixed

- **Progress Bar**:
  - Fixed progress bar crash at 100% (negative argument error)
  - Progress bar calculation uses `max(0, spaces)` to prevent negative values
- **Worker Verbosity**:
  - Fixed workers not picking up verbosity changes
  - Removed cached `@verbosity` from worker initialization
  - Workers now call `load_verbosity` dynamically
- **Configuration Tests**:
  - Fixed 7 failing ConfigurationLoader specs with proper worker model stubs
  - Tests now properly stub all required config calls
- **Debug Output Verbosity**:
  - Standardized "no work found" messages to verbosity level 3
  - Added message to ConversationSummarizer
  - Changed ExchangeSummarizer and EmbeddingGenerator from level 1 to level 3

### Removed

- **Man-page Infrastructure**:
  - Removed man-page indexing/storage to dedicate embeddings to conversational memory
  - Deleted ManPage indexers/tools and integration points
  - Purged man_page rows from embeddings table
- **Old Embeddings Command**:
  - Removed old `embeddings_command.rb` (replaced by `/worker embeddings`)
  - Updated command registration and help text

### Technical Details

- **Test Coverage**: 1,839 tests passing (from 680 in v0.10.0)
  - Line coverage: 98.91% (up from 97.64%)
  - Branch coverage: 90.76% (up from 89.22%)
  - Added 1,159 new test cases
- **Quality Metrics**:
  - Zero RuboCop violations maintained
  - TDD methodology followed throughout (Red → Green → Refactor)
  - Comprehensive test coverage for all new features
- **Database Migrations**:
  - 3 migrations applied for embeddings schema evolution
  - Foreign key constraints and indexes added
  - VSS index creation for vector similarity search
- **Performance**:
  - VSS-based RAG retrieval latency < 500ms (p90)
  - Efficient chunked I/O for backup operations (8 KB chunks)
  - Batch embedding requests to minimize API calls
- **Documentation**:
  - Created `docs/proposal-console-io-progress-support.md`
  - Comprehensive inline documentation (YARD format)
  - Updated help text for all new commands

### References

- Implements Issue #17: v0.11: Conversational Memory - RAG Foundation
- Implements Issue #5: Pausable Background Tasks
- Closes Issue #9: Add /backup command
- Related Issue #25: Real-time progress display (future enhancement)
- Related Issue #23: Granular debug verbosity control (future enhancement)

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

[0.11.0]: https://github.com/mgreenly/nu-agent/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/mgreenly/nu-agent/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/mgreenly/nu-agent/releases/tag/v0.9.0
