# Formatter Refactoring Goal

## Objective
Reduce `lib/nu/agent/formatter.rb` from **338 lines → ~200 lines** to eliminate ClassLength violation.

## Current State
- File: `lib/nu/agent/formatter.rb` (469 total lines, class: 338)
- **Violations:**
  - ClassLength: 338/250 (88 lines over limit) ⚠️
  - `display_message`: CyclomaticComplexity 11/10
  - `display_llm_request`: AbcSize 53.82, CyclomaticComplexity 20, MethodLength 35

## Target State
- Formatter < 250 lines (removes ClassLength violation)
- Extract formatting logic into dedicated classes
- Keep Formatter as coordinator
- All tests passing

## Key Methods (by line count)
1. `display_tool_call` - 43 lines (tool call formatting with verbosity)
2. `display_assistant_message` - 48 lines (content, tool calls, tokens, timing)
3. `display_llm_request` - 35 lines (most complex: AbcSize 53.82, Complexity 20)
4. `display_system_message` - 28 lines
5. Format helpers: `format_hash_result`, `format_truncated_value`, `format_full_value`, `format_simple_result` - ~40 lines total
6. Other: `display_thread_event` (15), `display_message_created` (20), `display_spell_checker_message` (10)

## Dependencies to Preserve
Formatter uses: `@console`, `@history`, `@orchestrator`, `@application`, `@debug`, `@conversation_id`, `@session_start_time`, `@exchange_start_time`, `@last_message_id`

## Extraction Strategy (High Level)
Extract formatters into separate classes:
- Tool formatters (display_tool_call, display_tool_result, format_* helpers) - ~100 lines
- Message formatters (display_assistant_message, display_user_message, etc.) - ~100 lines
- LLM request formatter (display_llm_request) - ~35 lines

This gets us from 338 → ~100 lines in Formatter (70% reduction!)

## Success Criteria
- ✅ Formatter < 250 lines
- ✅ All 413 tests passing
- ✅ New formatter classes are well-tested (TDD)
- ✅ ClassLength violation removed
- ✅ Complexity violations reduced/eliminated
- ✅ Zero behavior changes

## Reference
Current offense count: 164 offenses total
Target: Remove 1 ClassLength violation
