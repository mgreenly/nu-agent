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

## Phase 2: Integrate Exchanges into Flow (CURRENT)

### Tasks
- [ ] Modify `process_input` to create exchange at the start
- [ ] Update `chat_loop` to accept and track `exchange_id`
- [ ] Pass `exchange_id` to all `add_message` calls
- [ ] Complete the exchange when `chat_loop` finishes
- [ ] Handle exchange completion on errors and aborts
- [ ] Test that exchanges are created/completed correctly

### Notes
- Track exchange metrics: tokens, spend, message count, tool call count
- Set exchange status appropriately: 'in_progress', 'completed', 'failed', 'aborted'

---

## Phase 3: Enhanced Debug Verbosity

### Tasks
- [ ] Update verbosity levels in Formatter:
  - **Level 0**: Tool name only ("Using file_read")
  - **Level 1**: Tool name + first 30 chars of each param
  - **Level 2**: Tool name + full params (current behavior)
  - **Level 3**: Level 2 + show markdown document sent to LLM
  - **Level 4**: Level 3 + show conversation history
- [ ] Test each verbosity level

### Notes
- Current implementation already has some verbosity support (see formatter.rb:172-220)
- Extend this pattern for levels 3-4

---

## Phase 4: Markdown Document Builder

### Tasks
- [ ] Create `DocumentBuilder` class
  - [ ] `add_section(title, content)` - add a markdown section
  - [ ] `build` - return complete markdown string
- [ ] Add RAG context section (placeholder for now)
- [ ] Add tool descriptions section (placeholder for now)
- [ ] Add user query section
- [ ] Refactor `chat_loop` to use DocumentBuilder
- [ ] Test with simple markdown (no threading yet)

### Notes
- Document structure:
  ```markdown
  # Context
  [RAG results here]

  # Available Tools
  [Tool descriptions here]

  # User Request
  [User's message]
  ```

---

## Phase 5: Threaded Context Building

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

## Phase 6: Polish

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

---

## Version History

- v0.5.0 - Base version before refactoring (2025-10-24)
- v0.6.0 - (Planned) After Phase 1 completion (database schema changes)
