Nu-Agent v0.12 Plan: UX, Observability, and Maintainability

Last Updated: 2025-10-29
Target Version: 0.12.0
Plan Status: Draft for execution after v0.11 ships

Index
- High-level motivation
- Scope (in)
- Scope (out)
- Key technical decisions and hints
- Implementation phases
  - Phase 1: Event-driven message display (Observer)
  - Phase 2: ConsoleIO State Pattern
  - Phase 3: Operability — failed jobs and admin commands
  - Phase 4: Metrics and environment defaults
  - Phase 5: Privacy — redaction and purge
  - Phase 6: RAG refinements and caching
  - Phase 7: Migrations and developer workflow polish
- Success criteria
- Risks and mitigations
- Notes


High-level motivation
- Consolidate and refine the RAG-based conversational memory introduced in v0.11 by improving user experience, reliability, and operability.
- Remove remaining architectural friction: eliminate polling for message display, simplify ConsoleIO through a State Pattern, and make background work inspectable and recoverable.
- Strengthen privacy and governance: optional redaction on storage and a purge capability.

Scope (in)
- Event-driven message display (Observer) to replace polling and reduce DB chatter.
- ConsoleIO State Pattern refactor to clarify input/streaming/command handling.
- Operability: failed_jobs storage and commands; richer metrics; environment-aware worker defaults.
- Privacy: optional redaction pipeline and purge command.
- RAG refinements: filters (namespace/tags/time-range), recency weighting parameter, lightweight caching for common queries, and simple retrieval logging for observability.
- Migrations: finalize the minimal framework started in v0.11 and document workflow.

Scope (out)
- New retrieval modalities (web search/tools) and agent tool decorators beyond basic logging/metrics (target v0.13).
- Model/provider changes beyond what’s necessary for stability.

Key technical decisions and hints
- Observer pattern: Use a thread-safe event bus within the Application process. MessageStream (Observable) publishes events: user_input_received, assistant_token_streamed, exchange_completed, worker_status_updated. ConsoleView and any loggers subscribe. Avoid DB polling in the chat loop.
- ConsoleIO State Pattern: Introduce explicit states (Idle, ReadingUserInput, StreamingAssistant, CommandMode, Paused). Each state owns its transitions and rendering responsibilities. This reduces branching in ConsoleIO and prevents input/output interleaving bugs.
- Failed jobs: Add failed_jobs table with job_type, ref_id (e.g., exchange_id), payload, error, failed_at, retry_count. Workers write here after terminal failure. Provide admin commands to list, inspect, and retry.
- Metrics: Counters and timers collected in-memory with periodic snapshot to DB for inspection; expose via commands. Track processed/failed/retried, queue depth, batch latencies, API rate limit backoffs, and RAG retrieval latencies (p50/p90/p99).
- Privacy: Redaction hook in summarization/embedding paths. Start with regex-based scrub for common secrets (tokens, emails, keys) and allow custom patterns via config. Purge command must delete summaries/embeddings for a scope and rebuild as needed. Provide dry-run.
- Caching: Small in-memory LRU for RAG retrieval keyed by rounded query embeddings and config knobs; include TTL and invalidate on new writes to relevant conversations. Keep it opt-in and bounded to avoid stale/bloated context.
- RAG parameters: Support namespace/tag/time-range filters and a tunable recency weight alpha; preserve token budget and global caps from v0.11.
- RAG logging: Add rag_retrieval_logs table to capture query characteristics, candidate counts, scores, filtering applied, cache hits, and retrieval latency; enables validation of automatic RAG effectiveness without the complexity of v0.13's deep search logging.
- Migrations: Keep versioned files in migrations/. Ensure schema_version monotonic progression, idempotency, and rollback guidance for risky steps. Do not rely on IF NOT EXISTS for structural changes.

Implementation phases

Phase 1: Event-driven message display (Observer) (2–3 hrs) ✅ COMPLETED
Goal: Replace polling with an in-process event bus and subscribers.
Tasks
- ✅ Introduce EventBus (publish/subscribe) with thread-safe queues and bounded buffers.
- ✅ Emit events from key points: user input start/end, exchange committed.
- ✅ Replace chat loop polling with subscription to EventBus; Formatter subscribes to exchange_completed event.
- ✅ Backward compatibility maintained with polling fallback when event_bus is not available.
Validation
- ✅ Chat loop remains responsive, no duplicated messages.
- ✅ All 1864 tests passing with 98.74% line coverage / 90.85% branch coverage.
Testing
- ✅ Unit tests for EventBus publish/subscribe and ordering guarantees (25 tests).
- ✅ Integration tests updated for event flow from ChatLoopOrchestrator to Formatter.
Implementation Notes
- Created EventBus class with thread-safe publish/subscribe pattern
- Added EventBus to Application initialization
- ChatLoopOrchestrator emits user_input_received and exchange_completed events
- Formatter subscribes to events and uses event-driven wait_for_completion (with polling fallback)
- All existing tests updated to mock event_bus where needed

Phase 2: ConsoleIO State Pattern (2–3 hrs) ✅ COMPLETED
Goal: Simplify ConsoleIO logic by modeling explicit states.
Tasks
- ✅ Define states and transitions: Idle → ReadingUserInput → StreamingAssistant → Idle; Idle → Progress → Idle; any → Paused.
- ✅ Encapsulate per-state rendering and input handling. Ensure clean cancellation and Ctrl-C behavior.
- ✅ Remove conditional logic based on @mode and replace with State Pattern.
Validation
- ✅ Clean transitions when switching between states. No lost inputs; no interleaved output.
- ✅ All 1884 tests passing with 98.65% line coverage / 90.71% branch coverage.
Testing
- ✅ Unit tests for all states (IdleState, ReadingUserInputState, StreamingAssistantState, ProgressState, PausedState).
- ✅ Unit tests for state transitions and invalid transition detection.
- ✅ 20 new tests added for State Pattern behavior.
Implementation Notes
- Created State Pattern with base State class and 5 concrete states
- ConsoleIO delegates to current state via @state variable (replaces @mode)
- Each state owns valid transitions and raises StateTransitionError for invalid ones
- Internal do_* methods contain actual implementation logic
- States can be paused from any state and resumed to previous state
- All existing tests updated to work with State Pattern

Phase 3: Operability — failed jobs and admin commands (2 hrs)
Goal: Make background failures visible and recoverable.
Tasks
- Migration: create failed_jobs table (job_type, ref_id, payload JSON, error TEXT, retry_count, failed_at).
- Workers: on terminal failure, record into failed_jobs. Provide helper to enqueue retry.
- Commands: /admin failures [--type=], /admin show <id>, /admin retry <id>, /admin purge-failures [--older-than].
Validation
- Induce failures in tests and verify they appear and can be retried.
Testing
- Unit tests for persistence and command flows.

Phase 4: Metrics and environment defaults (1.5–2 hrs)
Goal: Increase visibility and make CI friendly.
Tasks
- Add counters/timers for workers and RAG retrieval. Compute p50/p90/p99.
- Expose via /summarizer, /embeddings, and /rag metrics.
- Default worker auto-start off in CI (ENV flag) and on in dev; document.
Validation
- Commands display metrics; CI runs without background churn.
Testing
- Unit tests for metric aggregation; integration test asserting CI default behavior.

Phase 5: Privacy — redaction and purge (2–3 hrs)
Goal: Provide basic privacy controls for stored summaries/embeddings.
Tasks
- Add redaction filter step configurable via ConfigStore (regex patterns and toggles). Apply before persisting summaries/embeddings.
- Implement /admin purge scope: conversation <id> | namespace <tag> | all. Transactionally delete embeddings and summaries as requested; optionally re-embed after purge.
- Document risks and limitations of regex-based redaction; allow plugging in a custom filter object.
Validation
- Redaction removes targeted tokens; purge deletes rows and rebuilds when requested.
Testing
- Unit tests for redaction and purge flows, including dry-run.

Phase 6: RAG refinements and caching (2.5–3.5 hrs)
Goal: Improve relevance, latency, and observability of automatic RAG.
Tasks
- Add namespace/tag filters to retrieval processors and commands.
- Add basic time-range filtering: recent (last N days), older (before N days ago), between dates; make configurable via commands.
- Implement recency weight parameter alpha; default small tie-break; make configurable.
- Introduce opt-in LRU cache keyed by rounded query embedding + config; TTL and invalidation on writes to involved conversations.
- Add simple RAG retrieval logging to rag_retrieval_logs table:
  - id, query_hash (for grouping similar queries), timestamp
  - conversation_candidates, exchange_candidates, retrieval_duration_ms
  - top_conversation_score, top_exchange_score
  - filtered_by (time_range, namespace, tags if applicable)
  - cache_hit boolean
- Maintain token budget and global caps; verify cache respects them.
Validation
- p90 retrieval improves with cache on repeated queries; relevance remains good.
- Time filters correctly limit candidate pool; logs enable validation of automatic RAG effectiveness.
Testing
- Unit tests for filters (namespace/tag/time), cache hit/miss behavior; integration test for invalidation on new summaries.
- Verify rag_retrieval_logs captures expected metrics.

Phase 7: Migrations and developer workflow polish (1 hr)
Goal: Solidify migration ergonomics and documentation.
Tasks
- Add generator Rake task to create timestamped migration files with up/down skeletons.
- Document migration workflow in docs and guardrails (no destructive changes without backups).
Validation
- New migration generated and applied in a smoke run.

Success criteria
- UX: Smooth, non-polling message display; clean console behavior across states; responsive streaming.
- Operability: Operators can view and retry failed jobs; metrics visible with p90s for workers and RAG.
- Privacy: Redaction can be enabled; purge operates safely with confirmations and dry-run.
- Performance: With VSS, retrieval p90 remains < 500ms; with cache on repeated queries, p90 improves measurably. CPU usage reduced vs polling.
- Maintainability: Clear stateful ConsoleIO; migration workflow is simple and reliable.

Risks and mitigations
- Event floods: Use bounded queues and drop/merge policy for non-critical events (e.g., coalesce worker status updates).
- Redaction false positives/negatives: Start conservative; allow opt-out and custom filters.
- Cache staleness: Keep TTL short; invalidate on writes to relevant conversations.
- Command complexity: Keep admin commands minimal and focused; extend only as needed.

Notes
- Preserve the ethos: tests accompany each phase; no instance_variable_get hacks; parameterized SQL; explicit types.
- RAG retrieval logging provides lightweight observability of automatic RAG performance without the complexity of v0.13's deep search logging; helps validate that automatic retrieval is working effectively and informs tuning decisions.
- Defer tool decorators and broader telemetry integrations to v0.13 to keep v0.12 focused on UX and operability.