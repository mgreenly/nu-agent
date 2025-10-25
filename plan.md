# Nu-Agent Refactoring Plan

## Overview

Major refactoring to introduce **exchanges** as a core concept and implement structured context building with RAG and tool description threading.

## Goals

1. Add `exchanges` table to group messages into logical units (user request → final response)
2. Implement multipart markdown document builder for context
3. Add parallel RAG threads for context gathering
4. Add tool description thread (with future subagent filtering)
5. Enhance debug verbosity levels (0-4)

---

## Phase 1: Database Foundation ✅ COMPLETE

### Tasks
- [x] Add `exchanges` table to schema
- [x] Add `exchange_id` column to `messages` table
- [x] Update History class with exchange methods:
  - [x] `create_exchange(conversation_id, user_message)` - returns exchange_id
  - [x] `update_exchange(exchange_id, updates)` - update status, completed_at, metrics, etc.
  - [x] `complete_exchange(exchange_id, summary, assistant_message, metrics)` - mark complete
  - [x] `get_exchange_messages(exchange_id)` - get all messages for an exchange
  - [x] `get_conversation_exchanges(conversation_id)` - get all exchanges in conversation
- [x] Test schema changes work correctly

### Notes
- Remember to bump minor version (0.5.0 → 0.6.0) when adding schema changes
- Use idempotent operations in `setup_schema` method

---

## Phase 2: Integrate Exchanges into Flow ✅ COMPLETE

### Tasks
- [x] Modify `process_input` to create exchange at the start
- [x] Update `chat_loop` to accept and track `exchange_id`
- [x] Pass `exchange_id` to all `add_message` calls
- [x] Complete the exchange when `chat_loop` finishes
- [x] Handle exchange completion on errors and aborts
- [x] Test that exchanges are created/completed correctly

### Notes
- Track exchange metrics: tokens, spend, message count, tool call count
- Set exchange status appropriately: 'in_progress', 'completed', 'failed', 'aborted'
- Exchange created after spell check, before user message added
- All messages in an exchange have the same exchange_id
- Metrics calculated throughout chat_loop and saved on completion

---

## Phase 3: Enhanced Debug Verbosity ✅ COMPLETE

### Tasks
- [x] Update verbosity levels in Formatter:
  - **Level 0**: Tool name only (no parameters shown)
  - **Level 1**: Tool name + up to 30 chars per param + thread lifecycle events
  - **Level 2**: Tool name + full params (current behavior)
  - **Level 3**: Level 2 + show messages sent to LLM
  - **Level 4**: Level 3 + show tools array
- [x] Test each verbosity level
- [x] Add thread lifecycle notifications for exchange-related threads

### Notes
- Implemented 5 distinct verbosity levels (0-4)
- Level 1 shows thread start/finish for Orchestrator (exchange threads)
- Levels 3-4 show complete LLM request context
- All 20 new verbosity specs pass

---

## Phase 4: Markdown Document Builder ✅ COMPLETE

### Tasks
- [x] Create `DocumentBuilder` class
  - [x] `add_section(title, content)` - add a markdown section
  - [x] `build` - return complete markdown string
- [x] Add RAG context section (placeholder for now)
- [x] Add tool descriptions section (lists all available tools)
- [x] Refactor `chat_loop` to use DocumentBuilder
- [x] Test with simple markdown (no threading yet)

### Notes
- Created DocumentBuilder with simple API: add_section(title, content) and build()
- Context document is prepended to first exchange message only
- Document structure:
  ```markdown
  # Context
  (RAG context will be added in Phase 5)

  # Available Tools
  tool1, tool2, tool3, ...
  ```
- All 14 DocumentBuilder specs pass
- Integration tested and working in chat_loop

---

## Phase 5: Architecture Redesign ✅ COMPLETE

### Overview
Major architectural redesign to separate message storage from LLM context building.

### Tasks
- [x] Redesign spell checker as RAG sub-process
- [x] Create inner `tool_calling_loop` function
- [x] Refactor `chat_loop` to use new architecture
- [x] Remove old redaction logic
- [x] Update verbosity display for new architecture
- [x] Test the complete redesign (all 154 specs passing)

### Architecture Changes

**Old Architecture (Pre-Phase 5):**
- User messages were modified (spell checked) before saving
- Markdown document prepended as user message to history
- Complex post-turn redaction marking via `mark_turn_as_redacted`
- Redaction index built by comparing before/after messages

**New Architecture (Post-Phase 5):**
1. **Message Storage**: User messages saved unmodified to database
2. **Redaction**: Messages created with `redacted=true` flag from the start (in `tool_calling_loop`)
3. **Context Building**: Markdown document built per exchange with:
   - RAG context (redacted ranges, spell check results, fun facts)
   - Available tools list
   - Original user query
4. **LLM Request**: Sends conversation history + markdown document where:
   - Conversation history = unredacted messages from **previous exchanges only** (current conversation)
   - Markdown document = context for the **current exchange**
   - Not saved this way (history and document sent separately but not stored as such)
5. **Spell Checking**: Now a RAG sub-process that adds corrections to context
6. **Inner/Outer Loop**:
   - Outer (`chat_loop`): Build context, call inner loop, save final response
   - Inner (`tool_calling_loop`): Handle tool calling iterations, save as redacted

### What Gets Saved as Redacted
- Tool calls (assistant messages with tool_calls)
- Tool results (role='tool')
- Intermediate LLM responses during tool calling

### What Gets Saved as Unredacted
- Original user queries
- Final LLM responses (no tool calls)
- Error messages (so user can see them)

### Removed Methods
- `redact_old_tool_results` - No longer needed
- `get_redacted_message_ranges` - Replaced by simple filtering
- `message_was_redacted?` - No longer needed
- `mark_turn_as_redacted` - Commented out (messages now created as redacted)

### Notes
- All existing specs continue to pass (154/154)
- Simpler redaction logic: `messages.reject { |m| m['redacted'] }`
- Spell checker results appear in RAG context, not as separate messages
- Future expansion: acronyms, jargon translation, clarity improvements

---

## Phase 6: Orchestrator Ownership & Transaction-Based Exchanges ✅ COMPLETE

### Overview
Major architectural refactoring to give the orchestrator full ownership of exchange processing with atomic transactions.

### Goals
1. Per-thread database connections (eliminate global mutex bottleneck)
2. Orchestrator owns entire exchange lifecycle (create → process → complete)
3. Atomic exchanges via transactions (all-or-nothing saves)
4. Clean rollback on interruption (no orphaned exchanges)

### Tasks
- [x] Refactor History to use per-thread connections
  - [x] Replace single `@conn` with connection pool (`@connections`)
  - [x] Add `connection` method for thread-local connection access
  - [x] Remove all `@mutex.synchronize` blocks around queries
  - [x] Keep `@connection_mutex` only for connection pool management
  - [x] Update `close` method to close all pooled connections
- [x] Add transaction support to History class
  - [x] Implement `transaction(&block)` method
  - [x] Auto-commit on success, auto-rollback on exception
- [x] Move exchange creation into chat_loop (orchestrator owns exchange)
  - [x] Change `chat_loop` signature from `exchange_id:` to `user_input:`
  - [x] Wrap entire `chat_loop` in `history.transaction do` block
  - [x] Create exchange inside transaction
  - [x] Add user message inside transaction
  - [x] Process and complete exchange inside transaction
- [x] Simplify process_input (just spawn orchestrator with raw input)
  - [x] Remove exchange creation from `process_input`
  - [x] Pass `user_input:` to `chat_loop` instead of `exchange_id:`
  - [x] Update thread to capture and pass raw user input
- [x] Remove exchange abort logic from process_input
  - [x] Remove `update_exchange(..., status: 'aborted')` on Ctrl-C
  - [x] Transaction rollback handles cleanup automatically
  - [x] No orphaned exchanges in database
- [x] Test the refactored flow
  - [x] All 154 specs pass
  - [x] Manual testing confirms correct behavior

### Architecture Changes

**Old Architecture:**
- Single shared database connection with global mutex
- Exchange created in `process_input` before orchestrator runs
- User message saved before orchestrator runs
- Aborted exchanges marked in database with status='aborted'
- Serialized database access (one thread at a time)

**New Architecture (Post-Phase 6):**
1. **Per-Thread Connections**: Each thread has its own DuckDB connection
2. **Orchestrator Ownership**: Orchestrator fully owns exchange lifecycle
3. **Atomic Exchanges**: `history.transaction do` wraps entire exchange
4. **Clean Rollback**: Ctrl-C or crash → transaction rolls back → no database trace
5. **Concurrent Access**: Multiple orchestrator threads can access DB simultaneously
6. **Long-Running Transactions**: Orchestrator holds transaction for entire exchange duration (safe with per-thread connections)

**Transaction Outcomes:**
- ✅ **Success**: Thread completes → transaction commits → exchange saved
- ✅ **Error**: Thread raises exception → transaction rolls back → nothing saved
- ✅ **Interrupt**: User hits Ctrl-C → thread killed → transaction rolls back → nothing saved

### Benefits
- **Atomicity**: Either complete exchange exists or nothing exists (no partial data)
- **Concurrency**: Multiple orchestrators can run in parallel without blocking
- **Simplicity**: Cleaner error handling, no special abort logic needed
- **Consistency**: Database always in consistent state (no orphaned exchanges)
- **Performance**: Eliminates global mutex bottleneck for database access

### Notes
- DuckDB's MVCC handles concurrent transactions well
- Per-thread connections eliminate lock contention
- Long orchestrator transactions don't block other threads
- Summarizer thread also benefits from per-thread connection
- All tests continue to pass (154/154)

---

## Phase 7: Threaded Context Building

### Tasks
- [ ] Implement RAG thread(s)
  - [ ] Search similar exchanges (by summary)
  - [ ] Search messages (full-text)
  - [ ] Other context gathering strategies
  - [ ] Join all RAG threads and collect results
- [ ] Implement Tool Description thread
  - [ ] Initially: return all tool descriptions
  - [ ] Future: subagent filters based on query
- [ ] Integrate threads with DocumentBuilder
- [ ] Test threaded flow

### Notes
- RAG threads run in parallel
- Tool description thread runs in parallel with RAG
- All threads must complete before building final document
- Consider timeout/deadline for thread completion

---

## Phase 7: Polish

### Tasks
- [ ] Add exchange summarization (similar to conversation summarization)
- [ ] Consider background worker for exchange summaries
- [ ] Test end-to-end flow
- [ ] Update documentation

---

## Success Criteria

- Exchanges are created and tracked correctly in database
- Context building happens in parallel threads
- Debug verbosity levels work as specified
- Performance is acceptable (threading doesn't slow things down)
- Code is cleaner and more maintainable than before
- **All features have comprehensive specs that pass**

## Testing Policy

Starting from Phase 2 onwards:
- Every phase must have comprehensive RSpec tests
- Tests must pass before phase is considered complete
- Tests cover happy path, edge cases, and error conditions
- Use descriptive test names that document behavior

---

## Data Migration

Existing messages can have NULL exchange_id. To migrate old data:

1. Run `/migrate-exchanges` command in the REPL
2. Analyzes all conversations and creates exchanges retroactively
3. Groups messages intelligently based on user messages
4. Safe to run - won't duplicate existing exchanges

## Version History

- v0.5.0 - Base version before refactoring (2025-10-24)
- v0.6.0 - Phase 1 complete: exchanges table and migration (2025-10-24)
