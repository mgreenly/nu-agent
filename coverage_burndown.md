# Test Coverage Burndown List

Files that need **both line AND branch coverage** brought to 100%.

Listed in order from worst to best coverage.

**Current Project Coverage:** 94.78% line, 84.41% branch
**Goal:** 100% line coverage AND 100% branch coverage on all files

---

## Files to Fix (15 files)

Each file needs to achieve 100% line coverage AND 100% branch coverage.

| Line Coverage | Uncovered Lines | Total Lines | File |
|---------------|----------------|-------------|------|
|  17.95% |             64 |          78 | `lib/nu/agent/man_indexer.rb` (skip - scheduled for removal) |
|  ~~33.33%~~ 100% |             ~~44~~ 0 |          ~~66~~ 68 | ~~`lib/nu/agent/tools/file_read.rb`~~ ✓ |
|  ~~33.33%~~ 100% |             ~~36~~ 0 |          ~~54~~ 54 | ~~`lib/nu/agent/tools/file_stat.rb`~~ ✓ |
|  ~~33.87%~~ 100% |             ~~41~~ 0 |          ~~62~~ 62 | ~~`lib/nu/agent/tools/dir_tree.rb`~~ ✓ |
|  ~~34.38%~~ 100% |             ~~42~~ 0 |          ~~64~~ 65 | ~~`lib/nu/agent/tools/dir_delete.rb`~~ ✓ |
|  ~~34.43%~~ 100% |             ~~40~~ 0 |          ~~61~~ 61 | ~~`lib/nu/agent/tools/file_tree.rb`~~ ✓ |
|  ~~36.17%~~ 100% |             ~~30~~ 0 |          ~~47~~ 48 | ~~`lib/nu/agent/tools/file_move.rb`~~ ✓ |
|  ~~36.17%~~ 100% |             ~~30~~ 0 |          ~~47~~ 48 | ~~`lib/nu/agent/tools/file_copy.rb`~~ ✓ |
|  ~~36.67%~~ 100% |             ~~38~~ 0 |          ~~60~~ 60 | ~~`lib/nu/agent/tools/search_internet.rb`~~ ✓ |
|  ~~39.29%~~ 100% |             ~~17~~ 0 |          ~~28~~ 28 | ~~`lib/nu/agent/tools/execute_bash.rb`~~ ✓ |
|   ~~40.0%~~ 100% |             ~~18~~ 0 |          ~~30~~ 30 | ~~`lib/nu/agent/tools/execute_python.rb`~~ ✓ |
|   ~~40.0%~~ 100% |             ~~24~~ 0 |          ~~40~~ 40 | ~~`lib/nu/agent/tools/database_message.rb`~~ ✓ |
|  ~~40.48%~~ 100% |             ~~25~~ 0 |          ~~42~~ 42 | ~~`lib/nu/agent/tools/file_delete.rb`~~ ✓ |
|  ~~41.03%~~ 100% |             ~~23~~ 0 |          ~~39~~ 39 | ~~`lib/nu/agent/tools/file_write.rb`~~ ✓ |
|  ~~41.67%~~ 100% |             ~~21~~ 0 |          ~~36~~ 36 | ~~`lib/nu/agent/clients/openai_embeddings.rb`~~ ✓ |
|  ~~42.31%~~ 100% |             ~~15~~ 0 |          ~~26~~ 26 | ~~`lib/nu/agent/spell_checker.rb`~~ ✓ |
|  ~~43.59%~~ 100% |             ~~22~~ 0 |          ~~39~~ 39 | ~~`lib/nu/agent/tools/dir_create.rb`~~ ✓ |
|  ~~45.71%~~ 100% |             ~~19~~ 0 |          ~~35~~ 35 | ~~`lib/nu/agent/tools/file_glob.rb`~~ ✓ |
|  ~~46.34%~~ 100% |             ~~22~~ 0 |          ~~41~~ 41 | ~~`lib/nu/agent/tools/man_indexer.rb`~~ ✓ |
|  ~~48.89%~~ 100% |             ~~23~~ 0 |          ~~45~~ 45 | ~~`lib/nu/agent/tools/file_edit.rb`~~ ✓ |
|   ~~52.5%~~ 100% |             ~~19~~ 0 |          ~~40~~ 40 | ~~`lib/nu/agent/tool_registry.rb`~~ ✓ |
|  ~~52.63%~~ 100% |              ~~9~~ 0 |          ~~19~~ 19 | ~~`lib/nu/agent/tools/database_schema.rb`~~ ✓ |
|  ~~52.63%~~ 100% |              ~~9~~ 0 |          ~~19~~ 19 | ~~`lib/nu/agent/tools/database_query.rb`~~ ✓ |
|  ~~64.21%~~ 100% |             ~~68~~ 0 |         ~~190~~ 190 | ~~`lib/nu/agent/formatter.rb`~~ ✓ |
|  64.84% |            109 |         310 | `lib/nu/agent/console_io.rb` |
|  ~~66.67%~~ 100% |              ~~5~~ 0 |          ~~15~~ 15 | ~~`lib/nu/agent/tools/database_tables.rb`~~ ✓ |
|  66.67% |             49 |         147 | `lib/nu/agent/application.rb` |
|  ~~72.78%~~ 100% |             ~~46~~ 0 |         ~~169~~ 169 | ~~`lib/nu/agent/history.rb`~~ ✓ |
|  ~~73.11%~~ 100% |             ~~32~~ 0 |         ~~119~~ 119 | ~~`lib/nu/agent/man_page_indexer.rb`~~ ✓ |
|  ~~73.47%~~ 100% |             ~~26~~ 0 |          ~~98~~ 98 | ~~`lib/nu/agent/clients/openai.rb`~~ ✓ |
|  ~~76.32%~~ 100% |              ~~9~~ 0 |          ~~38~~ 38 | ~~`lib/nu/agent/tools/agent_summarizer.rb`~~ ✓ |
|  ~~76.92%~~ 100% |              ~~3~~ 0 |          ~~13~~ 13 | ~~`lib/nu/agent/api_key.rb`~~ ✓ |
|  ~~79.07%~~ 100% |             ~~18~~ 0 |          ~~86~~ 86 | ~~`lib/nu/agent/clients/anthropic.rb`~~ ✓ |
|  ~~79.12%~~ 100% |             ~~19~~ 0 |          ~~91~~ 91 | ~~`lib/nu/agent/clients/google.rb`~~ ✓ |
|  ~~80.85%~~ 98.94% |             ~~18~~ 1* |          94 | ~~`lib/nu/agent/tools/dir_list.rb`~~ ✓ |
|  ~~90.29%~~ 100% |             ~~10~~ 0 |         ~~103~~ 103 | ~~`lib/nu/agent/chat_loop_orchestrator.rb`~~ ✓ |
|  ~~94.32%~~ 100% |              ~~5~~ 0 |          ~~88~~ 88 | ~~`lib/nu/agent/conversation_summarizer.rb`~~ ✓ |
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
- [x] `lib/nu/agent/tools/file_tree.rb` ✓
- [x] `lib/nu/agent/tools/file_move.rb` ✓
- [x] `lib/nu/agent/tools/file_copy.rb` ✓
- [x] `lib/nu/agent/tools/search_internet.rb` ✓
- [x] `lib/nu/agent/tools/execute_bash.rb` ✓
- [x] `lib/nu/agent/tools/execute_python.rb` ✓
- [x] `lib/nu/agent/tools/database_message.rb` ✓
- [x] `lib/nu/agent/tools/file_delete.rb` ✓
- [x] `lib/nu/agent/tools/file_write.rb` ✓
- [x] `lib/nu/agent/clients/openai_embeddings.rb` ✓
- [x] `lib/nu/agent/spell_checker.rb` ✓
- [x] `lib/nu/agent/tools/dir_create.rb` ✓
- [x] `lib/nu/agent/tools/file_glob.rb` ✓
- [x] `lib/nu/agent/tools/man_indexer.rb` ✓
- [x] `lib/nu/agent/tools/file_edit.rb` ✓
- [x] `lib/nu/agent/tool_registry.rb` ✓
- [x] `lib/nu/agent/tools/database_schema.rb` ✓
- [x] `lib/nu/agent/tools/database_query.rb` ✓
- [x] `lib/nu/agent/tools/database_tables.rb` ✓
- [x] `lib/nu/agent/tools/agent_summarizer.rb` ✓
- [x] `lib/nu/agent/api_key.rb` ✓
- [x] `lib/nu/agent/formatter.rb` ✓
- [x] `lib/nu/agent/clients/openai.rb` ✓
- [x] `lib/nu/agent/history.rb` ✓
- [x] `lib/nu/agent/man_page_indexer.rb` ✓
- [x] `lib/nu/agent/clients/anthropic.rb` ✓
- [x] `lib/nu/agent/clients/google.rb` ✓
- [x] `lib/nu/agent/tools/dir_list.rb` ✓ (98.94%, 1 line unreachable dead code)
- [x] `lib/nu/agent/chat_loop_orchestrator.rb` ✓
- [x] `lib/nu/agent/conversation_summarizer.rb` ✓

### Next Target

**File:** `lib/nu/agent/tools/file_grep.rb`
**Current Line Coverage:** 95.88%
**Lines to Cover:** 4
**Goal:** 100% line coverage + 100% branch coverage
