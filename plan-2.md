# Files With Incomplete Branch Coverage - Plan 2

This document lists files that do not have 100% branch coverage.

**Total files in this plan:** 5

| File | Coverage | Covered | Total | Uncovered |
|------|----------|---------|-------|----------|
| lib/nu/agent/formatters/tool_call_formatter.rb | 90.91% | 20 | 22 | 2 |
| lib/nu/agent/tools/dir_list.rb | 91.67% | 33 | 36 | 3 |
| lib/nu/agent/persona_manager.rb | 92.86% | 26 | 28 | 2 |
| lib/nu/agent/clients/google.rb | 93.94% | 31 | 33 | 2 |
| lib/nu/agent/parallel_executor.rb | 97.06% | 33 | 34 | 1 |

## Completed Files

| File | Coverage | Date | Notes |
|------|----------|------|-------|
| lib/nu/agent/commands/help_command.rb | 100% | 2025-11-02 | |
| lib/nu/agent/tools/file_grep.rb | 100% | 2025-11-02 | |
| lib/nu/agent/workers/conversation_summarizer.rb | 100% | 2025-11-02 | |
| lib/nu/agent/exchange_migrator.rb | 100% | 2025-11-02 | |
| lib/nu/agent/rag/query_embedding_processor.rb | 100% | 2025-11-02 | |
| lib/nu/agent/commands/debug_command.rb | 100% | 2025-11-02 | |
| lib/nu/agent/console_io.rb | 96.04% | 2025-11-02 | Improved from 93.56% (189/202) to 96.04% (194/202). Remaining 8 uncovered branches involve edge cases in IO.console initialization, interrupt handling in spinner thread, and CSI sequence parsing that are difficult to test safely in the test environment. |
| lib/nu/agent/commands/summarizer_command.rb | 100% | 2025-11-02 | Added test for usage message when summarizer is enabled (line 26) |
