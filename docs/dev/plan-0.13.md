Nu-Agent Plan: Deep Memory Search

Last Updated: 2025-10-29
Plan Status: Ready to execute

Index
- High-level motivation
- Scope (in)
- Scope (out, future enhancements)
- Key technical decisions and hints
- Implementation phases
  - Phase 1: Schema additions and FTS indexes
  - Phase 2: Hybrid retrieval implementation
  - Phase 3: Re-ranking pipeline
  - Phase 4: Tool integration and result formatting
  - Phase 5: Commands, configuration, and observability
- Success criteria
- Risks and mitigations
- Future enhancements
- Notes


High-level motivation
- Provide a deep memory search tool that the LLM can explicitly invoke when it needs comprehensive historical context beyond automatic RAG.
- Enable exhaustive search across all conversations and exchanges using hybrid retrieval strategies (VSS + BM25) combined with LLM re-ranking.
- Accept longer latency (10-30s) in exchange for maximal recall and relevance - this is a deliberate, high-value search the LLM requests when needed.
- Leverage available computational resources (high CPU cores, memory, storage) for parallel execution and quality over speed.
- Establish logging infrastructure to validate search strategies against outcomes and enable continuous improvement.

Scope (in)
- Deep memory search tool that LLM can invoke via function calling with query, optional time range, and configuration parameters.
- Hybrid retrieval: VSS semantic search + BM25 full-text search with score normalization and recency boosting.
- Full-text indexing on conversations.summary, exchanges.summary_text, exchanges.user_message, and exchanges.assistant_message.
- Parallel candidate retrieval strategies running concurrently.
- LLM-based re-ranking using configurable cheaper model (haiku/gpt-4o-mini) with batched parallel requests.
- Structured JSON response format with relevance scores, metadata, and search statistics.
- Time-range filtering support (before/after/between dates).
- Comprehensive logging in deep_search_logs table for strategy validation and cost tracking.
- Fail-fast error handling with clear notifications.
- Commands for configuration, testing, and observability.
- Cost accounting integrated into session tracking.

Scope (out, future enhancements)
- Thread expansion (finding related conversations mentioned in results).
- Entity extraction and graph traversal.
- Query expansion and iterative refinement.
- Cross-encoder models for re-ranking.
- HyDE (Hypothetical Document Embeddings).
- MMR (Maximal Marginal Relevance) diversity scoring.
- Learned relevance feedback loops.
- Cached frequent queries.
- Multi-turn deep search sessions.
- A/B testing framework for ranking strategies.
- User feedback collection on result quality.
- Random model selection from pool with statistical analysis.

Key technical decisions and hints
- Hybrid scoring: Combine normalized BM25 and VSS scores with recency boost. Initial weights: 0.35 × bm25 + 0.55 × vss + 0.10 × recency. Make configurable for tuning.
- Score normalization: Use min-max or z-score normalization so BM25 and cosine similarity scores are comparable.
- FTS strategy: DuckDB's fts extension on all relevant text fields (summaries and raw messages) for comprehensive keyword matching.
- Parallel retrieval: Run VSS conversation search, VSS exchange search, BM25 conversation search, and BM25 exchange search concurrently in threads; merge and deduplicate.
- Re-ranking batches: Group candidates into batches of 15-20; run multiple batches in parallel (4-8 concurrent requests); use cheaper model to control costs.
- Re-ranking prompt: Design to elicit numeric scores (0.0-1.0) with brief reasoning; emphasize semantic relevance, technical accuracy, and completeness.
- Result structure: Structured JSON with type, id, title, timestamp, relevance_score, summary, and aggregate stats (total candidates, duration, cost).
- Max results: Configurable, default 10, hard cap 30 to respect token budgets.
- Time filtering: Support before/after/between parameters on tool invocation; filter candidates during retrieval phase.
- Recency boost: Score boost based on age (e.g., exponential decay from present); applied during hybrid scoring.
- Logging schema: Capture query, all phase timings, candidate counts by strategy, re-ranking model/cost, final results, success/error in deep_search_logs table - enables retrospective analysis. This is distinct from and more comprehensive than rag_retrieval_logs which tracks automatic RAG; deep search logs include hybrid strategy breakdown and re-ranking metrics.
- Fail-fast philosophy: If critical components fail (VSS, FTS, re-ranking), surface error immediately rather than degrading silently; user/LLM can retry or adjust.
- Cost tracking: Re-ranking calls are part of session cost accounting; displayed in real-time session summary.
- SQL safety: Parameterized queries throughout; verify FTS query syntax to prevent injection.
- Model configuration: Single configurable re-ranking model initially; foundation for future experiments with multiple models.

Implementation phases

Phase 1: Schema additions and FTS indexes (1-1.5 hrs)
Goal: Add full-text search indexes and logging infrastructure.
Tasks
- Verify exchanges.summary_text column exists; if not, add migration.
- Create FTS indexes via migration
  - CREATE INDEX IF NOT EXISTS fts_conversation_summary ON conversations USING fts(summary)
  - CREATE INDEX IF NOT EXISTS fts_exchange_summary ON exchanges USING fts(summary_text)
  - CREATE INDEX IF NOT EXISTS fts_exchange_user_msg ON exchanges USING fts(user_message)
  - CREATE INDEX IF NOT EXISTS fts_exchange_assistant_msg ON exchanges USING fts(assistant_message)
- Create deep_search_logs table
  - id, search_id (UUID), query, timestamp
  - total_candidates, vss_candidates, bm25_candidates, retrieval_duration_ms
  - reranking_model, reranking_batches, reranking_duration_ms, reranking_cost_usd
  - final_result_count, top_result_score
  - total_duration_ms, success, error_message
- Add typed config getters for deep search parameters (max_results, hybrid_weights, reranking_model, etc.).
Testing
- Verify FTS indexes created successfully.
- Insert test log entry and query it.
- Confirm typed config reads work.

Phase 2: Hybrid retrieval implementation (3-4 hrs)
Goal: Implement parallel VSS + BM25 retrieval with hybrid scoring.
Tasks
- Implement CandidateRetriever with parallel search strategies
  - VSSConversationSearcher: top-K conversations by cosine similarity
  - VSSExchangeSearcher: top-K exchanges by cosine similarity
  - BM25ConversationSearcher: FTS search across conversations.summary
  - BM25ExchangeSearcher: FTS search across all 4 indexed fields (summary_text, user_message, assistant_message)
- Run all 4 searchers in parallel threads; collect and merge results.
- Deduplication: merge conversation/exchange results by ID.
- Score normalization: normalize BM25 scores and VSS scores to 0-1 range (min-max or z-score).
- Recency boost: calculate age-based boost (e.g., exponential decay with configurable half-life); add to normalized scores.
- Hybrid scoring: combine normalized BM25, VSS, and recency with configured weights (default 0.35/0.55/0.10).
- Time filtering: if time_range specified, filter candidates by created_at.
- Return sorted candidates with hybrid scores.
Testing
- Unit tests for each searcher independently.
- Integration test: run all 4 in parallel, verify deduplication and scoring.
- Test time filtering with before/after/between.
- Verify score normalization produces 0-1 range.

Phase 3: Re-ranking pipeline (3-4 hrs)
Goal: LLM-based re-ranking with parallel batched requests.
Tasks
- Implement LLMReranker with configurable model.
- Design re-ranking prompt (iterate during implementation):
  - Clear instructions for scoring 0.0-1.0
  - Emphasize semantic relevance, technical accuracy, completeness
  - Return structured JSON with id, score, brief reasoning
- Batch candidates into groups of 15-20.
- Run batches in parallel (4-8 concurrent requests depending on candidate count).
- Parse responses; extract scores; handle malformed responses gracefully (log warning, use fallback score).
- Aggregate scores across batches.
- Track token usage and compute cost (use provider-reported usage).
- Log re-ranking phase: model, batches, duration, cost.
- Sort candidates by re-ranked score.
Testing
- Unit tests: batch creation, prompt formatting, response parsing, error handling.
- Mock LLM responses for deterministic tests.
- Integration test with real (or test) LLM: verify parallel execution, cost computation.
- Test malformed response handling.

Phase 4: Tool integration and result formatting (2-3 hrs)
Goal: Expose deep_memory_search tool and format structured results.
Tasks
- Implement DeepMemorySearchTool
  - Register with ToolRegistry
  - Tool schema: query (required), time_range (optional: before/after/between), max_results (optional, default 10)
  - Orchestrate phases: retrieval → re-ranking → formatting
  - Generate search_id (UUID) for logging correlation
  - Log all phases to deep_search_logs
- Result formatter
  - Build structured JSON response
  - Include: results array (type, id, title, created_at, relevance_score, summary, exchange_count if conversation)
  - Include: stats (total_candidates, duration_ms, reranking_cost_usd)
  - Limit results to max_results (default 10, cap 30)
- Error handling: fail fast on critical errors; log error_message; return error to LLM.
- Cost integration: add re-ranking cost to session cost tracking.
Testing
- End-to-end integration test: invoke tool with query, verify JSON structure.
- Test time_range filtering.
- Test max_results parameter and cap.
- Test error scenarios (VSS unavailable, FTS fails, re-ranking fails).
- Verify cost added to session tracking.

Phase 5: Commands, configuration, and observability (1.5-2 hrs)
Goal: Provide operator visibility and control.
Commands
- /deep_search config
  - Show current configuration (hybrid weights, max_results, reranking_model, etc.)
  - Set parameters: set_weight bm25=0.4 vss=0.5 recency=0.1
  - Set max_results, set reranking_model
- /deep_search test <query>
  - Manual test with optional time_range
  - Display full results and timing breakdown
  - Show per-phase metrics (retrieval: Xms, re-ranking: Yms, formatting: Zms)
- /deep_search stats
  - Show aggregate statistics from deep_search_logs
  - Total searches, average duration, total cost, success rate
  - Top queries (if useful)
Metrics/Status
- Expose deep_search_logs table via read-only queries.
- Consider: recent searches with outcomes.
Testing
- Command parsing and validation.
- Config setters update configuration correctly.
- Test command displays results and metrics.
- Stats command aggregates log data correctly.

Success criteria
- Functional: LLM can invoke deep_memory_search tool; returns structured JSON with relevant results; hybrid retrieval finds content that pure VSS or BM25 alone would miss.
- Performance: Deep search completes within 30s for typical queries (100-200 candidates, re-ranking batches); parallel execution demonstrates speedup over serial.
- Correctness: Hybrid scoring combines VSS, BM25, and recency correctly; time filtering works; max_results respected; cost accurately tracked.
- Logging: All searches logged to deep_search_logs with complete metrics; data enables retrospective analysis of strategy effectiveness.
- Error handling: Failures in VSS, FTS, or re-ranking surface clear errors; no silent degradation; user/LLM can diagnose and retry.
- Observability: Commands provide visibility into configuration, manual testing, and aggregate statistics.
- Tests: Per-phase unit tests; end-to-end integration tests; manual validation against real conversation history.

Risks and mitigations
- FTS performance on large datasets: Use DuckDB's native fts which is optimized; test with realistic data volume; add row caps if needed.
- Re-ranking cost variance: Use cheaper models (haiku/gpt-4o-mini); track cost per search; make model configurable; display costs in real-time.
- Score normalization edge cases: Test with empty result sets, single results, identical scores; use robust normalization (handle division by zero).
- Parallel re-ranking failures: Implement retry logic for individual batches; log failures; continue with partial results if majority succeed; surface warning if too many fail.
- Hybrid weight tuning: Start with reasonable defaults based on research; log strategy contributions; adjust based on real usage data over time.

Future enhancements
- Query expansion: Use LLM to generate alternative phrasings and synonyms; search with expanded queries for better recall.
- Thread expansion: Follow conversation references in results; recursively search for related discussions.
- Entity extraction: Identify class names, commands, people, features; build knowledge graph; traverse graph for semantic search.
- Cross-encoder re-ranking: Use dedicated cross-encoder models (more accurate than LLM prompting) for final re-ranking stage.
- HyDE: Generate hypothetical ideal answer to query; embed and search with that; improves retrieval for abstract questions.
- MMR diversity: Penalize redundant results; ensure diverse coverage of topics/time periods.
- Learned relevance: Capture user/LLM feedback on result quality; train re-ranking model or adjust weights based on feedback.
- Cached queries: Cache frequent or recent deep search results; return instantly if query matches.
- Multi-turn deep search: Allow LLM to iteratively refine search (initial broad search → analyze → focused follow-up search).
- A/B testing framework: Randomly select from multiple ranking strategies; compare effectiveness via logged metrics.
- Random model selection: Choose re-ranking model from pool randomly; analyze which models perform best via statistics.
- User feedback integration: Allow explicit thumbs up/down on search results; feed into relevance learning.
- Advanced recency models: Configurable decay functions (linear, exponential, step); domain-specific recency (e.g., recent for bugs, any time for design decisions).
- Result snippets: Extract and highlight relevant passages from conversations/exchanges; show in results for quick scanning.
- Conversation retrieval tool: Separate tool for LLM to request full conversation by ID after reviewing deep search results.

Notes
- Deep search is complementary to automatic RAG: RAG provides fast, always-on context; deep search provides exhaustive, deliberate exploration when needed.
- Logging is critical for validating hybrid search approach: track which strategies contribute to successful retrievals; adjust weights and tactics based on data. deep_search_logs is distinct from rag_retrieval_logs: the latter tracks automatic RAG performance with basic metrics, while deep search logs capture comprehensive hybrid strategy breakdown, re-ranking details, and costs.
- Start with opinionated defaults (weights, batch sizes, model) based on research and best practices; make configurable; tune based on real usage.
- Parallel execution is a first-class feature: leverage available hardware for speed; design for concurrent searchers and re-rankers from the start.
- Keep re-ranking prompt design iterative: test with real queries during implementation; refine based on quality of scores and reasoning.
- Consider result quality over token efficiency: structured JSON is verbose but enables LLM to make informed decisions about which conversations to explore further.
