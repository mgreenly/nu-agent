# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.14.0] - 2025-11-02

### Added

- **LLM Request Builder** (Issue #37): Complete refactor of LLM request preparation using builder pattern
  - **New `LLMRequestBuilder` Class**: Centralized builder with LLM-agnostic internal message format
    - Builder pattern for constructing requests with clean API
    - Internal format with metadata for debugging and observability
    - Separation between orchestration and API-specific formatting
    - Support for conversation history, system prompt, user query, and tool calling
  - **Unified Debug Output**: Consistent YAML debug output across all LLM clients
    - Verbosity levels 0-5 for fine-grained control
    - Level 0: No debug output
    - Level 1: Request metadata only (timestamp, model, temperature, token counts)
    - Level 2: Add conversation history (messages without content)
    - Level 3: Full conversation history with message content
    - Level 4: Add tool schemas and definitions
    - Level 5: Complete request dump including raw API format
  - **Client Refactoring**: All 4 LLM clients updated to use builder
    - Anthropic, OpenAI, Google, and XAI clients refactored
    - Consistent `build_request` method across all clients
    - Eliminated duplication in message content formatting
    - Proper handling of system prompts and tool calls
  - **RAG Content Structure**: Improved separation of RAG content from user queries
    - RAG content (redactions, spell check) stored in metadata hash
    - Clean separation in internal format between user query and augmentation
    - Proper token counting for all content types
  - **Performance Benchmarks**: Comprehensive benchmarking suite
    - Benchmark tests for builder performance across different scenarios
    - No performance regression verified
    - Optimized for both small and large conversation histories
  - **Test Coverage**: Extensive test additions
    - 892 lines of integration tests for LLMRequestBuilder
    - 241 lines of unit tests for the builder
    - Client-specific tests for all 4 LLM implementations
    - Orphaned code detection spec to ensure code quality
    - Total of 79 commits for this feature

### Changed

- **Verbosity System**: Expanded from 3 to 6 levels (0-5)
  - Enhanced `/verbosity` command with new levels
  - `/llm verbosity` now supports levels 0-5
  - Updated help text to document all verbosity levels
  - Consistent verbosity handling across all subsystems

- **LLM Request Formatting**: Major architectural improvements
  - Moved request building logic from orchestrators to dedicated builder
  - Simplified `ChatLoopOrchestrator` and `ToolCallOrchestrator`
  - Reduced code duplication across the codebase
  - Better separation of concerns

- **Documentation**: Added comprehensive development documentation
  - `docs/dev/plan-llm-request-builder.md` (693 lines) - Complete implementation plan
  - `docs/dev/testing-checklist-request-builder.md` (370 lines) - Testing checklist
  - Updated inline documentation for new components

### Fixed

- **Subsystem Command Parsing** (Issue #42 - Bug 1): Fixed command input parsing
  - `/llm help`, `/messages help`, and other subsystem commands now work correctly
  - `SubsystemCommand#execute` now properly strips command prefix before parsing
  - Fixes circular error: "Unknown subcommand: /llm" when typing "/llm help"
  - Commands work with both formats: with prefix ("/llm help") and without ("help")

- **Empty Tools Display**: Fixed verbosity level 4 showing empty tools
  - Tools section now properly hidden when no tools are available
  - Preserves tool structure display when tools exist

- **System Prompt Display**: Fixed system prompt not showing in debug output
  - System prompt now included in internal format
  - Properly displayed at appropriate verbosity levels

- **Tool Debug Messages at Verbosity 0**: Fixed tool use debug messages appearing when verbosity set to 0
  - Tool result formatter now properly checks verbosity before displaying any output
  - When tools verbosity is 0, no "[Tool Use Response]" messages are shown
  - Updated tests to reflect correct behavior

### Removed

- **Spell checker functionality**: Removed spell checker feature and all related code (Issue #29)
  - Removed `/spellcheck` command
  - Removed `/debug spellcheck` debug command
  - Removed `SpellChecker` class and implementation
  - Removed spell checker from `Application`, `ConfigurationLoader`, and `SessionInfo`
  - Removed spell checker subsystem from `VerbosityCommand`
  - Removed all spell checker tests and documentation
  - Note: Old database config values (`model_spellchecker`, `spell_check_enabled`) will remain but are unused

- **Backup file**: Removed accidentally committed `application.rb.bak` file (1,646 lines)

### Technical Details

- **Files Changed**: 37 files modified across the implementation
- **Code Impact**:
  - 4,083 insertions (+)
  - 1,989 deletions (-)
  - Net gain: 2,094 lines of code
- **Test Coverage**: Maintained high standards
  - Line coverage: 99.43% (increased from previous threshold)
  - Branch coverage: 91.18% (increased from previous threshold)
- **Quality Metrics**:
  - Zero RuboCop violations maintained
  - TDD methodology followed throughout
  - Comprehensive test coverage for all new features
- **Performance**:
  - No performance regression in request building
  - Optimized YAML formatting for large conversations
  - Efficient handling of tool schemas at verbosity level 4
- **Code Organization**:
  - New `lib/nu/agent/llm_request_builder.rb` (210 lines)
  - Enhanced `lib/nu/agent/formatters/llm_request_formatter.rb` (233 lines changed)
  - Updated all client implementations in `lib/nu/agent/clients/`

### References

- Closes Issue #37: Refactor LLM request preparation with builder pattern and unified debug output
- Partially addresses Issue #42: Multiple bugs in subsystem commands (Bug 1 fixed)
- Closes Issue #29: Remove spell checker (completed)

## [0.13.0] - 2025-10-31

### Fixed

- **Post-merge hang issues**: Fixed critical bugs introduced by recent merges
  - Enabled exception reporting in orchestrator thread to debug silent failures
  - Added welcome message clarifying Enter submits and Shift+Enter for newlines
  - Issue: Enter key submits input, Shift+Enter inserts newlines for multiline editing
  - Previous behavior where Enter submitted input was changed but not clearly communicated

### Added

- **Switchable Agent Personas** (Issue #12): Custom system prompts for different agent behaviors
  - `PersonaManager` class for CRUD operations on personas
  - Database schema with `personas` table (name, system_prompt, is_default)
  - `/persona` command for managing personas (list, show, create, edit, delete, switch)
  - Editor integration for creating/editing personas in $EDITOR
  - `{{DATE}}` placeholder support in system prompts (auto-replaced with current date)
  - `/personas` alias for convenience
  - Active persona automatically loaded and applied to all LLM calls
  - Default persona system for fallback behavior
  - 61 new tests for PersonaManager and PersonaCommand

- **Parallel Tool Execution** (Issue #33): Concurrent execution of independent tool calls
  - **Tool Metadata System**: Extended ToolRegistry with operation_type (:read/:write) and scope (:confined/:unconfined)
  - **Dependency Analysis**: `PathExtractor` for extracting file paths from tool arguments
  - **Dependency Batching**: `DependencyAnalyzer` for grouping independent tool calls into batches
    - Read operations can run in parallel with other reads
    - Write operations must wait for prior writes to the same path
    - Unconfined tools (execute_bash) act as barriers, running in isolation
  - **Parallel Execution Engine**: `ParallelExecutor` using Ruby threads for concurrent execution
    - Thread-safe execution with proper exception handling
    - Results collected and returned in original order
    - Thread-safe History writes during parallel execution
  - **Observability**: Batch/thread visibility in debug output
    - Per-tool execution timing with start/end timestamps
    - API request timing visibility
    - Batch and thread numbering in formatted output
  - **Format Compatibility**: Support for both flat and nested tool_use formats from API clients
  - **Performance**: Comprehensive benchmarking suite for parallel execution scenarios
  - 156 new tests for parallel execution (PathExtractor, DependencyAnalyzer, ParallelExecutor, integration)

- **Multiline Editing Support** (Issue #22, #32): Full multiline input editing in ConsoleIO
  - **Line Navigation**: Arrow up/down for navigating within multiline input
  - **History Integration**: Arrow up on first line accesses history, arrow down on last line returns to current input
  - **Cursor Management**: Saved column position maintained during vertical navigation
  - **Display Rendering**: Proper multiline rendering with line wrapping support
  - **Submit Behavior**:
    - Enter key submits input
    - Shift+Enter (or Ctrl+J) inserts newline for multiline editing
  - **Edge Case Handling**: Fixed terminal wrapping, cursor positioning, and display bugs
  - **Testing**: 45+ integration tests for multiline workflows
  - Manual testing checklist for comprehensive validation

- **Granular Verbosity Control** (Issue #23): Subsystem-specific debug output control
  - **Subsystem Commands**: Individual commands for controlling debug output per subsystem
    - `/llm` - LLM request/response debug output (3 levels)
    - `/messages` - Message tracking/routing debug output (3 levels)
    - `/tools` - Tool call/result debug output (3 levels)
    - `/search` - Search command debug output (3 levels)
    - `/stats` - Statistics/timing/cost debug output (3 levels)
    - `/spellcheck` - Spell checker debug output (3 levels)
  - **SubsystemCommand Base Class**: Reusable pattern for subsystem commands with status/on/off/level support
  - **SubsystemDebugger Helper**: Centralized module for subsystem-specific debug checks
  - **Enhanced /verbosity Command**: Query all subsystem verbosity levels
  - **Configuration Storage**: Subsystem verbosity stored in appconfig as `<subsystem>_verbosity`
  - **Migration**: Converted parallel execution verbosity from global to subsystem-specific
  - **Testing**: 125+ new tests for subsystem commands and verbosity control
  - Thread-safety fixes for DuckDB access in SubsystemDebugger

### Changed

- **Test Coverage**: Increased to 99.61% line coverage / 91.59% branch coverage (from 98.91% / 90.76% in v0.11.0)
  - 2,430 total tests (up from 1,839)
  - Added 591 new test cases
- **Development Guidelines**:
  - Added git rebase guidelines to AGENT.md
  - Added plan execution guidelines with manual validation requirements
  - Prohibited use of git stash in development workflow
- **Documentation Organization**:
  - Moved developer documentation to `docs/dev/` subdirectory
  - Removed version number references from issues and plans for version-agnostic tracking
- **Debug Output Routing**: All API debug output now routed through ConsoleIO instead of STDERR
- **Output Visibility**: Fixed spinner visibility during parallel tool execution API waits
- **Code Quality**: Zero RuboCop violations maintained across all new code

### Fixed

- **Line Wrap Bug** (Issue #32): Fixed terminal line wrapping and display rendering issues
  - Multiline redraw bug: track cursor position between redraws
  - Navigation logic: empty buffer = history, non-empty = lines
  - Critical bug: treat 0 as valid cursor line, not uninitialized
  - Multiline submit display: clear from first line
- **Parallel Execution Streaming**: Fixed streaming output for parallel tool execution
- **Timing Display**: Fixed timing display to show actual timestamps instead of offsets
- **DuckDB Thread Safety**: Fixed thread-safety issue in SubsystemDebugger with flaky tests
- **Help Text**: Fixed subsystem command names in help output
- **Coverage Thresholds**: Maintained 0.02% margin above required thresholds

### Technical Details

- **Database Migrations**:
  - Migration 006: `personas` table with default persona support
  - All migrations idempotent and reversible
- **Performance**:
  - Parallel tool execution reduces latency for independent operations
  - Benchmarking suite for performance validation
- **Code Organization**:
  - Persona classes in `lib/nu/agent/persona_manager.rb` and `lib/nu/agent/persona_editor.rb`
  - Parallel execution in `lib/nu/agent/parallel_executor.rb` and `lib/nu/agent/dependency_analyzer.rb`
  - Subsystem commands in `lib/nu/agent/commands/subsystems/`
  - SubsystemDebugger in `lib/nu/agent/subsystem_debugger.rb`
- **Documentation**:
  - Added `manual-testing-checklist.md` for multiline editing validation
  - Added `docs/plan-granular-verbosity.md` with implementation details
  - Updated help text for all new commands

### References

- Closes Issue #12: Add switchable agent personas with custom system prompts
- Closes Issue #22: Minimal multiline editing support for ConsoleIO
- Closes Issue #23: Granular debug verbosity control
- Closes Issue #32: Fix line wrap bug in user prompt input
- Closes Issue #33: Implement parallel tool execution

## [0.12.0] - 2025-10-31

### Added

- **Event-Driven Message Display** (Phase 1): Eliminated polling-based message display with Observer pattern
  - `EventBus` class with thread-safe publish/subscribe pattern
  - Bounded queues for event delivery with subscriber management
  - Events emitted for key lifecycle points: `user_input_received`, `exchange_completed`
  - `Formatter` subscribes to events for responsive message display
  - Polling fallback maintained for backward compatibility
  - Reduces CPU usage and eliminates database polling in chat loop
  - 25 new tests for EventBus publish/subscribe and ordering guarantees

- **ConsoleIO State Pattern** (Phase 2): Refactored ConsoleIO from conditional logic to explicit state machine
  - Five distinct states: `IdleState`, `ReadingUserInputState`, `StreamingAssistantState`, `ProgressState`, `PausedState`
  - State-based transition validation with `StateTransitionError` for invalid transitions
  - Each state owns its rendering and input handling responsibilities
  - Safe pause/resume from any state with previous state restoration
  - Eliminates input/output interleaving bugs and conditional spaghetti
  - 20 new tests for state transitions and state-specific behaviors

- **Failed Jobs Tracking and Admin Commands** (Phase 3): Background work observability and recovery
  - `failed_jobs` table for terminal worker failures (job_type, ref_id, payload, error, retry_count, failed_at)
  - `FailedJobRepository` for CRUD operations and filtering
  - Workers automatically record failures with full context
  - `/admin failures [--type=]` - List failed jobs with filtering
  - `/admin show <id>` - Inspect detailed failure information
  - `/admin retry <id>` - Retry failed job by re-queuing
  - `/admin purge-failures [--older-than=]` - Clean up old failures
  - 19 new tests for FailedJobRepository and AdminCommand

- **Metrics Collection and CI-Friendly Defaults** (Phase 4): Performance observability and CI compatibility
  - `MetricsCollector` class with thread-safe counters and duration tracking
  - Timer statistics with p50/p90/p99 percentile calculations
  - Worker processing latencies tracked and displayed in status output
  - `/worker exchange-summarizer status` now shows performance metrics
  - Workers automatically skip auto-start when `CI=true` environment variable set
  - Prevents background worker churn during CI test runs
  - 16 new tests for MetricsCollector (counters, timers, percentiles, thread safety)

- **Privacy Controls** (Phase 5): Data redaction and purge capabilities
  - `RedactionFilter` class with configurable regex patterns
  - Default patterns for API keys, emails, bearer tokens, secrets
  - Custom patterns configurable via JSON in config store (requires double-escaping)
  - Redaction applied before persisting summaries and embeddings
  - `/admin purge conversation <id>` - Delete all data for a conversation
  - `/admin purge all` - Delete all summaries and embeddings (requires confirmation)
  - Dry-run support for preview without actual deletion
  - Transactional purge operations for consistency
  - 12 new tests for RedactionFilter, 7 tests for purge commands

- **RAG Retrieval Enhancements** (Phase 6): Advanced filtering, caching, and observability
  - **Time-Range Filtering**: `after_date` and `before_date` parameters through full RAG pipeline
  - **Recency Weighting**: Tunable `recency_weight` (alpha) parameter for blending similarity and recency scores
    - `alpha=1.0`: Pure similarity ranking (default)
    - `alpha=0.0`: Pure recency ranking
    - `alpha=0.5`: Balanced scoring
  - **RAG Cache**: Opt-in LRU cache with configurable TTL (default 5 minutes)
    - Thread-safe cache keyed by rounded query embeddings + config parameters
    - Cache hit/miss tracking via retrieval logger
    - Automatic cache invalidation on conversation writes
  - **Retrieval Logging**: `rag_retrieval_logs` table for automatic RAG observability
    - Tracks query_hash, candidate counts, scores, cache hits, duration
    - `RAGRetrievalLogger` class for logging and recent logs retrieval
    - Enables validation of automatic RAG effectiveness without manual queries
  - **Enhanced Search Methods**: `search_conversations` and `search_exchanges` in EmbeddingStore
    - JOIN support for fetching conversation/exchange metadata
    - Time-range filtering at SQL level for efficiency
  - 61 new tests for RAG enhancements (retrieval logger, time filters, recency weight, cache)

- **Migration Generator and Workflow** (Phase 7): Developer experience improvements
  - `MigrationGenerator` class for creating timestamped migration files
  - `rake migration:generate NAME=migration_name` task for easy migration creation
  - Follows Rails convention: `NNN_migration_name.rb` format
  - Supports CamelCase to snake_case conversion
  - Comprehensive migration workflow documentation in `docs/dev/migrations.md`
  - Best practices, guardrails, troubleshooting, and rollback guidance
  - 14 new tests for MigrationGenerator

### Changed

- **ConsoleIO Architecture**: Replaced mode-based conditionals with State Pattern
  - Removed `@mode` instance variable in favor of `@state`
  - State transitions now validated and explicit
  - Safer defensive cleanup with no-op `hide_spinner` in IdleState
  - Improved maintainability and testability

- **Worker Auto-Start Behavior**: Background workers respect CI environment
  - Workers check `ENV["CI"]` before auto-starting
  - Prevents unnecessary background processing during test runs
  - Reduces CI noise and resource usage

- **Coverage Enforcement**: Updated thresholds for combined v0.12 + main codebase
  - Line coverage: 98.15% (actual: 98.17%, margin: 0.02%)
  - Branch coverage: 90.00% (actual: 90.02%, margin: 0.02%)
  - Maintains project standard of 0.02% margin above required threshold

### Fixed

- **StateTransitionError in IdleState**: Added safe no-op `hide_spinner` method
  - Defensive cleanup calls no longer raise errors when already idle
  - Improves robustness during state transitions

- **Recency Weighting Edge Cases**: Fixed empty results handling
  - Tests updated to use date filters instead of unrealistic similarity thresholds
  - Proper handling when no results match time-range filters

- **RuboCop Compliance**: Added legitimate exclusions for new v0.12 code
  - `BackgroundWorkerManager`, `AdminCommand`, `ExchangeSummarizerCommand` method length exclusions
  - `History` purge transaction blocks require long blocks for atomicity
  - All exclusions documented with justification

### Technical Details

- **Test Coverage**: 2,138 tests passing (up from 1,839 in v0.11.0)
  - Line coverage: 98.17% (6,281 / 6,398 lines)
  - Branch coverage: 90.02% (1,543 / 1,714 branches)
  - Added 299 new test cases across all 7 phases
- **Quality Metrics**:
  - Zero RuboCop violations maintained (252 files inspected)
  - TDD methodology followed throughout (Red → Green → Refactor)
  - Comprehensive test coverage for all new features
- **Database Migrations**:
  - Migration 006: `failed_jobs` table for operational resilience
  - Migration 007: `rag_retrieval_logs` table for automatic RAG observability
  - All migrations idempotent and reversible
- **Performance**:
  - Event-driven architecture reduces CPU usage vs polling
  - RAG cache improves p90 latency on repeated queries
  - Worker metrics enable performance monitoring and optimization
- **Code Organization**:
  - State classes organized in `lib/nu/agent/console_io_states.rb`
  - Admin commands in `lib/nu/agent/commands/admin_command.rb`
  - Metrics collection in `lib/nu/agent/metrics_collector.rb`
  - Privacy controls in `lib/nu/agent/redaction_filter.rb`
  - RAG cache in `lib/nu/agent/rag_cache.rb`

### References

- Implements Issue #19: v0.12: RAG UX, Observability, and Maintainability
- Builds on Issue #17: v0.11: Conversational Memory - RAG Foundation

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
- **Future Planning**: Created `docs/dev/plan-0.11.md` with detailed v0.11 refactoring roadmap
- **Database Design Documentation**: Added `docs/dev/design-overview.md` documenting database schema and relationships
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
  - Moved `design.md` to `docs/dev/design-overview.md`
  - Created `docs/dev/architecture-analysis.md`
  - Created `docs/dev/plan-0.11.md`
- **Patterns Implemented**: WorkerToken (Token/Guard), SpinnerState (Value Object)
- **Database Safety**: Zero performance overhead with significant corruption risk reduction

## [0.9.0] - Previous Release

_(Earlier changelog entries to be added)_

---

[0.14.0]: https://github.com/mgreenly/nu-agent/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/mgreenly/nu-agent/compare/v0.11.0...v0.13.0
[0.12.0]: https://github.com/mgreenly/nu-agent/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/mgreenly/nu-agent/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/mgreenly/nu-agent/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/mgreenly/nu-agent/releases/tag/v0.9.0
