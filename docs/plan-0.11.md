Nu-Agent v0.11 Plan: Conversational Memory (RAG)

Last Updated: 2025-10-29
Target Version: 0.11.0
Plan Status: Ready to execute

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

Phase 0: Remove man-page infrastructure (30 min)
Goal: Remove man-page indexing/storage to dedicate embeddings to conversational memory.
Tasks
- Delete Man indexers/tools and remove integration points (BackgroundWorkerManager, ToolRegistry, requires).
- Purge man_page rows from text_embedding_3_small.
- Update docs/README to remove man references.
Validation
- No references to ManPage code; SELECT COUNT(*) WHERE kind='man_page' = 0; app boots; tests pass.

Phase 1: Database schema, VSS, and migrations (60–90 min)
Goal: Enable correct VSS usage with safe schema evolution and constraints.
Tasks
- Enable/LOAD vss extension; on failure, record fallback mode and continue.
- Introduce a minimal migration framework: schema_version table and migrations/ directory; apply pending migrations on startup.
- Add columns and constraints
  - conversation_id INTEGER REFERENCES conversations(id) ON DELETE CASCADE
  - exchange_id INTEGER REFERENCES exchanges(id) ON DELETE CASCADE
  - UNIQUE(kind, conversation_id) WHERE conversation_id IS NOT NULL
  - UNIQUE(kind, exchange_id) WHERE exchange_id IS NOT NULL
- Indexes
  - CREATE INDEX IF NOT EXISTS idx_embedding_conversation ON text_embedding_3_small(conversation_id)
  - CREATE INDEX IF NOT EXISTS idx_embedding_exchange ON text_embedding_3_small(exchange_id)
  - VSS index: CREATE INDEX IF NOT EXISTS embedding_vss_idx ON text_embedding_3_small USING vss(embedding) WITH(metric='cosine')
- EmbeddingStore search API
  - Implement conversation/exchange search using ORDER BY cosine_distance(embedding, :q) LIMIT :k (or vss_search) when VSS is loaded; linear-scan fallback with array_cosine_similarity otherwise.
  - Parameterize all SQL; add EXPLAIN checks in a debug path to confirm index usage.
- Typed config getters: get_int/get_float/get_bool; validate values.
Testing
- Unit test schema_version and migrations execution.
- Verify FK integrity, uniqueness constraints, and index creation (presence) with a smoke test.
- Gate VSS tests: when vss is unavailable, assert fallback search path is used; when available, assert EXPLAIN shows vss usage.

Phase 2: Exchange summarization worker (1.5–2 hrs)
Goal: Summarize each completed exchange and store summary + cost.
Tasks
- Implement ExchangeSummarizer worker (or adapt existing) with injected dependencies; no instance_variable_get or send hacks.
- Use client abstraction to obtain normalized text and token usage; compute and store actual cost.
- Respect critical sections via public methods; keep DB writes minimal; add jittered backoff and simple rate limiting.
- Optional redaction hook (no-op by default) to enable later privacy features.
Metrics/Status
- Track processed, failed, retries, last_batch_latency; expose via /summarizer.
Testing
- Unit tests: idle loop, signal handling, error/retry, cost accounting, redaction hook pass-through.

Phase 3: Embedding pipeline worker (2–3 hrs)
Goal: Generate embeddings for conversation and exchange summaries and upsert into store.
Tasks
- Implement EmbeddingPipeline with explicit item type discriminator; avoid inferring by timestamps.
- Batch requests; apply rate limiting and backoff with jitter; respect batch size from typed config.
- Upsert semantics: enforce uniqueness; replace on conflict; update updated_at; ensure ON DELETE CASCADE works.
- Record provider token usage and cost; surface metrics via /embeddings.
Testing
- Unit tests for queue discovery, batching, error/retry, upsert uniqueness, and cost storage.
- Integration test against DuckDB with small fixtures; verify uniqueness and cascade behavior.

Phase 4: RAG retrieval with Chain of Responsibility (3–4.5 hrs)
Goal: Retrieve relevant context via modular processors and build a token-budgeted prompt context.
Pipeline
- QueryEmbeddingProcessor: embed query once; cache per request.
- ConversationSearchProcessor: VSS-based top-K conversation summaries with exclude current option and min similarity.
- ExchangeSearchProcessor: per-conversation top-M exchanges; apply global cap across all exchanges; allow direct exchange-only search if no conversation meets threshold.
- ContextFormatterProcessor: token-budgeted document builder; allocate budget across conversations/exchanges (e.g., default 40% conversation summaries, 60% exchanges); similarity-primary with recency tie-break.
Technical notes
- Parameterize all queries; use EXPLAIN in dev to verify VSS usage.
- Replace Rails.logger references with project logger/output_line.
- Ensure provider-neutral response parsing through client abstraction.
SLA and measurement
- With VSS enabled: p90 retrieval latency < 500ms; add a manual test command to measure; log metrics to status output.
Testing
- Unit tests per processor; integration test for end-to-end retriever honoring budgets and caps; gated performance smoke test when VSS is available.

Phase 5: Commands and operability (1.5–2 hrs)
Goal: Give operators visibility and control.
Commands
- /summarizer: show status/metrics; start/stop; set rates.
- /embeddings: show status/metrics; start/stop; set batch size/rate; rebuild_embeddings with confirmation.
- /rag: enable/disable; set thresholds, budgets, caps; measure retrieval latency.
Stretch (if time permits)
- failed_jobs table and /admin view_failures, retry <id>.
Testing
- Command parsing/validation with typed config; rebuild confirmation flow; metrics visible.

Success criteria
- Functional: Exchange summaries and embeddings flow end-to-end; RAG context appears in responses and is relevant.
- Performance: With VSS, p90 retrieval < 500ms on test dataset; without VSS, fallback returns within bounded time due to caps/prefilter.
- Correctness and safety: No SQL string interpolation; uniqueness constraints enforced; costs computed from usage; workers are thread-safe and observable.
- Tests: Per-phase unit tests plus end-to-end retriever integration; VSS-gated tests pass or are skipped appropriately.

Risks and mitigations
- VSS unavailable: Fallback linear scan with caps, prominent warning, and docs in docs/duckdb-setup.md.
- Cost variance: Use provider-reported usage; document price config.
- Worker dead jobs: Stretch failed_jobs; otherwise expose metrics and logs for manual triage.

Out of scope (v0.12)
- Event-driven message display (Observer), ConsoleIO State Pattern, richer privacy redaction/purge, richer metrics and dashboards, caching layer, and advanced retrieval filters.

Notes
- Keep EXPLAIN handy during development to ensure index usage.
- Prefer small, targeted migrations; do not rely solely on IF NOT EXISTS for schema evolution.
- Use environment toggles to default worker auto-start off in CI.