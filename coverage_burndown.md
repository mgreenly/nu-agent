# Test Coverage Burndown List

Files that need **both line AND branch coverage** brought to 100%.

Listed in order from worst to best coverage.

**Current Project Coverage:** 75.32% line, 47.43% branch
**Goal:** 100% line coverage AND 100% branch coverage on all files

---

## Files to Fix (40 files)

Each file needs to achieve 100% line coverage AND 100% branch coverage.

| Line Coverage | Uncovered Lines | Total Lines | File |
|---------------|----------------|-------------|------|
|  17.95% |             64 |          78 | `lib/nu/agent/man_indexer.rb` (skip - scheduled for removal) |
|  ~~33.33%~~ 100% |             ~~44~~ 0 |          ~~66~~ 68 | ~~`lib/nu/agent/tools/file_read.rb`~~ ✓ |
|  ~~33.33%~~ 100% |             ~~36~~ 0 |          ~~54~~ 54 | ~~`lib/nu/agent/tools/file_stat.rb`~~ ✓ |
|  ~~33.87%~~ 100% |             ~~41~~ 0 |          ~~62~~ 62 | ~~`lib/nu/agent/tools/dir_tree.rb`~~ ✓ |
|  ~~34.38%~~ 100% |             ~~42~~ 0 |          ~~64~~ 65 | ~~`lib/nu/agent/tools/dir_delete.rb`~~ ✓ |
|  34.43% |             40 |          61 | `lib/nu/agent/tools/file_tree.rb` |
|  36.17% |             30 |          47 | `lib/nu/agent/tools/file_move.rb` |
|  36.17% |             30 |          47 | `lib/nu/agent/tools/file_copy.rb` |
|  36.67% |             38 |          60 | `lib/nu/agent/tools/search_internet.rb` |
|  39.29% |             17 |          28 | `lib/nu/agent/tools/execute_bash.rb` |
|   40.0% |             18 |          30 | `lib/nu/agent/tools/execute_python.rb` |
|   40.0% |             24 |          40 | `lib/nu/agent/tools/database_message.rb` |
|  40.48% |             25 |          42 | `lib/nu/agent/tools/file_delete.rb` |
|  41.03% |             23 |          39 | `lib/nu/agent/tools/file_write.rb` |
|  41.67% |             21 |          36 | `lib/nu/agent/clients/openai_embeddings.rb` |
|  42.31% |             15 |          26 | `lib/nu/agent/spell_checker.rb` |
|  43.59% |             22 |          39 | `lib/nu/agent/tools/dir_create.rb` |
|  45.71% |             19 |          35 | `lib/nu/agent/tools/file_glob.rb` |
|  46.34% |             22 |          41 | `lib/nu/agent/tools/man_indexer.rb` |
|  48.89% |             23 |          45 | `lib/nu/agent/tools/file_edit.rb` |
|   52.5% |             19 |          40 | `lib/nu/agent/tool_registry.rb` |
|  52.63% |              9 |          19 | `lib/nu/agent/tools/database_schema.rb` |
|  52.63% |              9 |          19 | `lib/nu/agent/tools/database_query.rb` |
|  64.21% |             68 |         190 | `lib/nu/agent/formatter.rb` |
|  64.84% |            109 |         310 | `lib/nu/agent/console_io.rb` |
|  66.67% |              5 |          15 | `lib/nu/agent/tools/database_tables.rb` |
|  66.67% |             49 |         147 | `lib/nu/agent/application.rb` |
|  72.78% |             46 |         169 | `lib/nu/agent/history.rb` |
|  73.11% |             32 |         119 | `lib/nu/agent/man_page_indexer.rb` |
|  73.47% |             26 |          98 | `lib/nu/agent/clients/openai.rb` |
|  76.32% |              9 |          38 | `lib/nu/agent/tools/agent_summarizer.rb` |
|  76.92% |              3 |          13 | `lib/nu/agent/api_key.rb` |
|  79.07% |             18 |          86 | `lib/nu/agent/clients/anthropic.rb` |
|  79.12% |             19 |          91 | `lib/nu/agent/clients/google.rb` |
|  80.85% |             18 |          94 | `lib/nu/agent/tools/dir_list.rb` |
|  90.29% |             10 |         103 | `lib/nu/agent/chat_loop_orchestrator.rb` |
|  94.32% |              5 |          88 | `lib/nu/agent/conversation_summarizer.rb` |
|  95.88% |              4 |          97 | `lib/nu/agent/tools/file_grep.rb` |
|   97.3% |              1 |          37 | `lib/nu/agent/exchange_repository.rb` |
|  97.78% |              1 |          45 | `lib/nu/agent/session_info.rb` |

---

## Progress Tracking

### Completed (100% line + 100% branch)
- [x] `lib/nu/agent/spinner.rb` ✓
- [x] `lib/nu/agent/options.rb` ✓
- [x] `lib/nu/agent/tools/file_read.rb` ✓
- [x] `lib/nu/agent/tools/file_stat.rb` ✓
- [x] `lib/nu/agent/tools/dir_tree.rb` ✓
- [x] `lib/nu/agent/tools/dir_delete.rb` ✓

### Next Target

**File:** `lib/nu/agent/tools/file_tree.rb`
**Current Line Coverage:** 34.43%
**Lines to Cover:** 40
**Goal:** 100% line coverage + 100% branch coverage
