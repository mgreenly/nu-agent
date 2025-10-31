Nu-Agent v0.11 Plan: Conversational Memory (RAG)

Last Updated: 2025-10-29
Target Version: 0.11.0
Plan Status: COMPLETE

Implementation Progress:
✅ Phase 0: Remove man-page infrastructure (COMPLETE)
✅ Phase 1: Database schema, VSS, and migrations (COMPLETE)
✅ Phase 2: Exchange summarization worker (COMPLETE)
✅ Phase 3: Embedding pipeline worker (COMPLETE)
✅ Phase 4: RAG retrieval with Chain of Responsibility (COMPLETE)
✅ Phase 5: Commands and operability (COMPLETE)

Index
- High-level motivation
- Scope (in)
- Scope (out, moved to v0.12)
- Key technical decisions and hints
- Implementation phases
  - Phase 0: Remove man-page infrastructure
  - Phase 1: Database schema, VSS, and migrations
  - Phase 2: Exchange summarization worker
  - Phase 3: Embedding pipeline worker
  - Phase 4: RAG retrieval with Chain of Responsibility
  - Phase 5: Commands and operability
- Success criteria
- Risks and mitigations
- Out of scope (v0.12)
- Notes


High-level motivation
- Give the agent durable conversational memory using Retrieval-Augmented Generation (RAG) so it can remember, reference, and build upon past interactions across conversations.
- Deliver meaningful capability with minimal churn: integrate a modular RAG pipeline now; defer larger UI/architecture refactors to v0.12.
- Maintain our ethos: tests per phase, clarity over cleverness, parameterized SQL, thread-safe workers, and observable behavior.

Scope (in)
- Exchange-level summarization, embeddings, and semantic retrieval across conversations/exchanges.
- Chain of Responsibility for the RAG pipeline from the start (processors modular and testable).
- Correct DuckDB VSS usage, with linear-scan fallback if VSS is unavailable.
- Basic worker hygiene, accurate cost accounting, token-budgeted context building, and minimal metrics surfaced via commands.

Scope (out, moved to v0.12)
- Event-driven message display (Observer) to replace polling.
- ConsoleIO State Pattern refactor.
- Privacy redaction pipeline and purge command (unless mandated sooner).
- Larger operability/observability upgrades and caching.

Key technical decisions and hints
- DuckDB VSS: Use the extension’s native index and query API so the index is actually used. Create index USING vss(embedding) with metric='cosine' (or current recommended form) and query with ORDER BY cosine_distance(embedding, :q) LIMIT k or via vss_search(...). Verify with EXPLAIN.
- Fallback path: If LOAD vss fails, gracefully degrade to linear scan using cosine similarity with a recency prefilter and hard row caps to bound latency.
- Data integrity: Add UNIQUE(kind, conversation_id) where conversation_id IS NOT NULL and UNIQUE(kind, exchange_id) where exchange_id IS NOT NULL; add ON DELETE CASCADE FKs for embeddings to conversations/exchanges.
- SQL safety: Replace string interpolation with prepared statements/parameter binding from DuckDB’s Ruby driver; centralize helpers in History/EmbeddingStore as needed.
- Typed config: Provide typed reads (int/float/bool) for limits, thresholds, batch sizes, and toggles.
- Workers: Remove reflection/reach-in; inject collaborators or expose explicit accessors; add jittered backoff and simple rate limiting; introduce an explicit type discriminator in embedding pipeline items.
- Cost accounting: Compute summarization/embedding cost from provider token usage and configured prices; store actual cost.
- RAG context quality: Implement a token-budgeted formatter with similarity as primary and recency as tie-break; enforce global caps across conversations/exchanges.
- Performance SLA: With VSS available, p90 RAG retrieval latency < 500ms on a reasonable dataset (e.g., a few thousand embeddings). Measure during manual tests and report via command.
- Testing: Tests are integrated per phase; VSS-dependent tests are gated and fall back to linear path if needed.

Implementation phases

Phase 0: Remove man-page infrastructure (30 min) ✅ COMPLETE
Status: Complete (commit: f200c7c)
Goal: Remove man-page indexing/storage to dedicate embeddings to conversational memory.
Tasks
- ✅ Delete Man indexers/tools and remove integration points (BackgroundWorkerManager, ToolRegistry, requires).
- ✅ Purge man_page rows from text_embedding_3_small.
- ✅ Update docs/README to remove man references.
Validation
- ✅ No references to ManPage code; SELECT COUNT(*) WHERE kind='man_page' = 0; app boots; tests pass.
- ✅ All 1567 tests passing after cleanup

Phase 1: Database schema, VSS, and migrations (60–90 min) ✅ COMPLETE
Status: Complete (commits: 53caa89, b07c0e2, 3b4ef9e)
Goal: Enable correct VSS usage with safe schema evolution and constraints.
Tasks
- ✅ Enable/LOAD vss extension; on failure, record fallback mode and continue.
- ✅ Introduce a minimal migration framework: schema_version table and migrations/ directory; apply pending migrations on startup.
- ✅ Add columns and constraints
  - ✅ conversation_id INTEGER REFERENCES conversations(id) ON DELETE CASCADE
  - ✅ exchange_id INTEGER REFERENCES exchanges(id) ON DELETE CASCADE
  - ✅ UNIQUE(kind, conversation_id) WHERE conversation_id IS NOT NULL
  - ✅ UNIQUE(kind, exchange_id) WHERE exchange_id IS NOT NULL
- ✅ Indexes
  - ✅ CREATE INDEX IF NOT EXISTS idx_embedding_conversation ON text_embedding_3_small(conversation_id)
  - ✅ CREATE INDEX IF NOT EXISTS idx_embedding_exchange ON text_embedding_3_small(exchange_id)
  - ✅ VSS index: CREATE INDEX IF NOT EXISTS embedding_vss_idx ON text_embedding_3_small USING HNSW(embedding) WITH(metric='cosine')
- ✅ EmbeddingStore search API
  - ✅ Implement conversation/exchange search using array_cosine_distance (VSS) and array_cosine_similarity (fallback)
  - ✅ Dual-mode operation: VSS with HNSW index when available, linear scan with prefiltering as fallback
  - ✅ Support for min_similarity threshold
- ✅ Typed config getters: get_int/get_float/get_bool; validate values with proper error messages.
Testing
- ✅ 13 tests for MigrationManager (schema_version, pending_migrations, rollback)
- ✅ 16 tests for typed config getters (validation, defaults, errors)
- ✅ 7 tests for EmbeddingStore search (VSS, linear scan, filtering, similarity)
- ✅ All 1574 tests passing (99.51% line coverage)

Phase 2: Exchange summarization worker (1.5–2 hrs) ✅ COMPLETE
Status: Complete (commit: eb92128)
Goal: Summarize each completed exchange and store summary + cost.
Tasks
- ✅ No migration needed: exchanges.summary column already exists in schema
- ✅ Implement ExchangeSummarizer worker with injected dependencies; uses critical sections properly
- ✅ Use client abstraction to obtain normalized text and token usage; compute and store actual cost
- ✅ Store generated summary in exchanges.summary column for each completed exchange
- ✅ Respect critical sections via public methods (enter_critical_section/exit_critical_section)
- ✅ Filter messages by exchange_id to isolate individual exchanges
- ✅ Filter out redacted messages from summary prompts
- ✅ Thread-safe status tracking with mutex
- ✅ Graceful shutdown handling during LLM calls
Metrics/Status
- ✅ Track processed, completed, failed, current_exchange_id, last_summary, spend
Testing
- ✅ 12 comprehensive tests: initialization, threading, error handling, shutdown, filtering
- ✅ Verify summary column is populated after summarization
- ✅ All 1586 tests passing (99.31% line coverage)

Phase 3: Embedding pipeline worker (2–3 hrs) ✅ COMPLETE
Status: Complete (commits: ec2b34f, 6a16d7e)
Goal: Generate embeddings for conversation and exchange summaries and upsert into store.
Tasks
- ✅ Implement EmbeddingPipeline with explicit item type discriminator; avoid inferring by timestamps
- ✅ Batch requests; apply rate limiting and backoff with jitter; respect batch size from typed config
- ✅ Upsert semantics: enforce uniqueness; replace on conflict; update updated_at; ensure ON DELETE CASCADE works
- ✅ Record provider token usage and cost; surface metrics via /embeddings
- ✅ Refactored to eliminate all RuboCop violations: extracted 15+ helper methods for clarity
Testing
- ✅ 7 comprehensive tests: queue discovery, batching, error/retry, upsert uniqueness, and cost storage
- ✅ All tests passing

Phase 4: RAG retrieval with Chain of Responsibility (3–4.5 hrs) ✅ COMPLETE
Status: Complete (commits: ec2b34f, 6a16d7e)
Goal: Retrieve relevant context via modular processors and build a token-budgeted prompt context.
Pipeline
- ✅ QueryEmbeddingProcessor: embed query once; cache per request
- ✅ ConversationSearchProcessor: VSS-based top-K conversation summaries with exclude current option and min similarity
- ✅ ExchangeSearchProcessor: per-conversation top-M exchanges; apply global cap across all exchanges; allow direct exchange-only search if no conversation meets threshold
- ✅ ContextFormatterProcessor: token-budgeted document builder; allocate budget across conversations/exchanges (default 40% conversation summaries, 60% exchanges); similarity-primary with recency tie-break
Technical notes
- ✅ Parameterize all queries; no string interpolation
- ✅ Provider-neutral response parsing through client abstraction
Testing
- ✅ 11 RAG processor tests: context formatting, retrieval, empty results, token budgets, metadata tracking
- ✅ All tests passing

Phase 5: Commands and operability (1.5–2 hrs) ✅ COMPLETE
Status: Complete (commits: ec2b34f, 6a16d7e)
Goal: Give operators visibility and control.
Commands
- ✅ /embeddings: show status/metrics; on/off; start; batch size/rate configuration; reset (clear all embeddings)
- ✅ /rag: show status; on/off; test <query> with latency measurement; configure all thresholds, budgets, caps
- ✅ Real-time metrics: progress, failures, spend, current items
- ✅ Refactored to eliminate all RuboCop violations: extracted 30+ helper methods across both commands
Testing
- ✅ 17 command tests: parsing, validation, configuration, status display
- ✅ All tests passing

Success criteria
- Functional: Exchange summaries and embeddings flow end-to-end; RAG context appears in responses and is relevant.
- Performance: With VSS, p90 retrieval < 500ms on test dataset; without VSS, fallback returns within bounded time due to caps/prefilter.
- Correctness and safety: No SQL string interpolation; uniqueness constraints enforced; costs computed from usage; workers are thread-safe and observable.
- Tests: Per-phase unit tests plus end-to-end retriever integration; VSS-gated tests pass or are skipped appropriately.

Risks and mitigations
- VSS unavailable: Fallback linear scan with caps, prominent warning, and docs in docs/setup-duckdb.md.
- Cost variance: Use provider-reported usage; document price config.
- Worker dead jobs: Stretch failed_jobs; otherwise expose metrics and logs for manual triage.

Out of scope (v0.12)
- Event-driven message display (Observer), ConsoleIO State Pattern, richer privacy redaction/purge, richer metrics and dashboards, caching layer, and advanced retrieval filters.

Notes
- Keep EXPLAIN handy during development to ensure index usage.
- Prefer small, targeted migrations; do not rely solely on IF NOT EXISTS for schema evolution.
- Use environment toggles to default worker auto-start off in CI.