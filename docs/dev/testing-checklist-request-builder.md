# LLM Request Builder Refactoring - Testing Checklist

**Plan Reference:** `docs/dev/plan-llm-request-builder.md` - Phase 7

**Purpose:** Manual validation of the LLM request builder refactoring to ensure all functionality works correctly across all LLM providers.

## Pre-Testing Setup

### Environment Verification
- [ ] Ensure all API keys are configured in environment
  - `ANTHROPIC_API_KEY`
  - `OPENAI_API_KEY`
  - `GOOGLE_API_KEY`
  - `XAI_API_KEY`
- [ ] Verify database is accessible: `$PWD/db/memory.db`
- [ ] Check current git branch: `issue-37-request-builder`
- [ ] Run tests to confirm baseline: `rake test && rake lint && rake coverage`

### Baseline Understanding
Review the refactoring changes:
- [x] Internal request format using `LlmRequestBuilder`
- [x] YAML debug output with verbosity levels (0-5)
- [x] Removed duplicate "Available Tools" section from message content
- [x] Client translation from internal format to provider-specific APIs

---

## Test Suite Organization

Each client should be tested with the following scenarios:
1. Simple query (no tools)
2. Query requiring tool use
3. Multi-turn conversation
4. Debug output at various verbosity levels
5. Verification of no tool name duplication

---

## 1. Anthropic Client Testing

### 1.1 Basic Functionality
- [ ] Start agent with Anthropic client
  ```bash
  # Set appropriate environment variable or config
  ```

- [ ] **Test: Simple Query (No Tools)**
  - [ ] Send: "What is 2 + 2?"
  - [ ] Verify: Response is received and correct
  - [ ] Verify: No errors in console output

- [ ] **Test: Tool Use**
  - [ ] Send: "What files are in the current directory?"
  - [ ] Verify: Agent calls appropriate tool (e.g., file listing)
  - [ ] Verify: Tool result is processed correctly
  - [ ] Verify: Final response incorporates tool results

- [ ] **Test: Multi-Turn Conversation**
  - [ ] Turn 1: "Hello, my name is Alex"
  - [ ] Turn 2: "What is my name?"
  - [ ] Verify: Agent remembers context from turn 1
  - [ ] Verify: History is maintained correctly

### 1.2 Debug Output Verification

- [ ] **Verbosity Level 0** (Silent)
  - [ ] Set verbosity to 0
  - [ ] Send any query
  - [ ] Verify: No "--- LLM Request ---" output appears

- [ ] **Verbosity Level 1** (Final User Message)
  - [ ] Set verbosity to 1
  - [ ] Send: "Test message"
  - [ ] Verify: Output shows only `final_message` field
  - [ ] Verify: Output is in YAML format with gray color

- [ ] **Verbosity Level 3** (+ RAG Content)
  - [ ] Set verbosity to 3
  - [ ] Send query that triggers RAG
  - [ ] Verify: Output includes `rag_content` if present
  - [ ] Verify: System prompt is shown

- [ ] **Verbosity Level 5** (Full History)
  - [ ] Set verbosity to 5
  - [ ] Send query in multi-turn conversation
  - [ ] Verify: Output shows complete `messages` array
  - [ ] Verify: All conversation history is visible
  - [ ] Verify: Tools are shown (if tools are enabled)

### 1.3 No Duplication Check
- [ ] Set verbosity to 5
- [ ] Send query that uses tools
- [ ] Verify: Tool names appear ONLY in `tools` section
- [ ] Verify: No "Available Tools:" section in message content
- [ ] Verify: User message content does not list tool names

---

## 2. OpenAI Client Testing

### 2.1 Basic Functionality
- [ ] Switch to OpenAI client
- [ ] **Test: Simple Query**
  - [ ] Send: "Explain quantum computing in one sentence"
  - [ ] Verify: Response received correctly

- [ ] **Test: Tool Use**
  - [ ] Send: "Search for information about Ruby programming"
  - [ ] Verify: Tool is called and result processed

- [ ] **Test: Multi-Turn Conversation**
  - [ ] Turn 1: "I'm working on a Ruby project"
  - [ ] Turn 2: "What language am I using?"
  - [ ] Verify: Context maintained

### 2.2 Debug Output Verification
- [ ] Test verbosity levels 0, 1, 3, 5 (same checks as Anthropic)
- [ ] Verify YAML format is consistent across clients

### 2.3 No Duplication Check
- [ ] Verify no tool name duplication in message content

---

## 3. Google Client Testing

### 3.1 Basic Functionality
- [ ] Switch to Google client
- [ ] **Test: Simple Query**
  - [ ] Send: "What is the capital of France?"
  - [ ] Verify: Response received correctly

- [ ] **Test: Tool Use**
  - [ ] Send query requiring tool use
  - [ ] Verify: Tool execution works

- [ ] **Test: Multi-Turn Conversation**
  - [ ] Test context retention across turns

### 3.2 Debug Output Verification
- [ ] Test verbosity levels 0, 1, 3, 5
- [ ] Verify YAML format consistency

### 3.3 No Duplication Check
- [ ] Verify no tool name duplication

---

## 4. XAI Client Testing

### 4.1 Basic Functionality
- [ ] Switch to XAI client
- [ ] **Test: Simple Query**
  - [ ] Send test query
  - [ ] Verify response

- [ ] **Test: Tool Use**
  - [ ] Test tool calling

- [ ] **Test: Multi-Turn Conversation**
  - [ ] Test context retention

### 4.2 Debug Output Verification
- [ ] Test verbosity levels 0, 1, 3, 5

### 4.3 No Duplication Check
- [ ] Verify no tool name duplication

---

## 5. Cross-Client Verification

### 5.1 Consistency Checks
- [ ] Debug output format is identical across all clients
- [ ] YAML structure matches expected schema
- [ ] Gray coloring (\e[90m) is applied consistently
- [ ] Verbosity filtering works the same way for all clients

### 5.2 Internal Format Validation
- [ ] All clients receive the same internal format structure
- [ ] Translation to provider APIs happens correctly
- [ ] No information is lost during translation

---

## 6. Special Feature Testing

### 6.1 Redaction Functionality
- [ ] Send message containing sensitive data (e.g., API key pattern)
- [ ] Set verbosity to 3 or higher
- [ ] Verify: Sensitive data is redacted in debug output
- [ ] Verify: Redaction still works as expected
- [ ] Check `rag_content` for redaction information

### 6.2 History Storage
- [ ] Start a new conversation
- [ ] Send several messages back and forth
- [ ] Exit the agent
- [ ] Restart the agent and reload conversation
- [ ] Verify: Full conversation history is retrieved
- [ ] Verify: Message storage in database is unaffected by refactoring
- [ ] Query database directly if needed:
  ```sql
  SELECT * FROM messages ORDER BY id DESC LIMIT 10;
  ```

### 6.3 RAG Content Display
- [ ] Trigger RAG content generation (spell check, redactions)
- [ ] Set verbosity to 3
- [ ] Verify: RAG content is displayed in debug output
- [ ] Verify: RAG content is properly structured in YAML

---

## 7. Edge Cases and Error Handling

### 7.1 Empty Messages
- [ ] Test with minimal/empty input scenarios
- [ ] Verify: Appropriate error handling

### 7.2 Long Conversations
- [ ] Test with long conversation history (10+ exchanges)
- [ ] Verify: Debug output at level 5 shows all messages
- [ ] Verify: No performance degradation

### 7.3 Tools Without Usage
- [ ] Send query that doesn't require tools
- [ ] Verify: Tools are still available but not called
- [ ] Verify: Debug output at level 4 shows available tools

### 7.4 Rapid Verbosity Changes
- [ ] Change verbosity level between requests
- [ ] Verify: New level takes effect immediately
- [ ] Verify: No stale state issues

---

## 8. Performance Validation

### 8.1 Response Time
- [ ] Record baseline response time before refactoring (if available)
- [ ] Measure response time after refactoring
- [ ] Verify: No significant overhead from builder pattern
- [ ] Target: <10ms overhead for request preparation

### 8.2 Memory Usage
- [ ] Monitor memory during extended session
- [ ] Verify: No memory leaks from builder or formatter
- [ ] Verify: YAML generation doesn't consume excessive memory

---

## 9. Documentation Verification

### 9.1 Code Documentation
- [ ] Review YARD docs in `LlmRequestBuilder`
- [ ] Review YARD docs in `LlmRequestFormatter`
- [ ] Verify: Examples in documentation are accurate
- [ ] Verify: Cross-references work correctly

### 9.2 Plan Accuracy
- [ ] Verify: Implementation matches plan specifications
- [ ] Verify: All success criteria from plan are met
- [ ] Verify: Internal format structure matches plan

---

## 10. Final Verification

### 10.1 Success Criteria Checklist (from plan)
- [ ] No duplication in message content (tool names not in message body)
- [ ] Consistent debug output format across all clients
- [ ] YAML debug output with verbosity filtering working
- [ ] All tests passing: `rake test && rake lint && rake coverage`
- [ ] No performance regression
- [ ] Tool calling loops still work correctly
- [ ] Redaction still works correctly
- [ ] History storage unaffected
- [ ] All tasks committed individually
- [ ] Plan document updated for all completed tasks

### 10.2 Regression Testing
- [ ] Run full test suite one final time: `rake test`
- [ ] Run linter: `rake lint`
- [ ] Verify coverage: `rake coverage`
- [ ] Check for any unexpected warnings or errors

---

## Testing Notes

Use this section to record observations, issues, or unexpected behavior:

### Client-Specific Notes

**Anthropic:**
-

**OpenAI:**
-

**Google:**
-

**XAI:**
-

### Issues Found
-

### Performance Observations
-

### Other Notes
-

---

## Sign-Off

When all checkboxes are complete and testing is successful:

- [ ] All manual tests completed
- [ ] No critical issues found
- [ ] All issues documented and resolved or tracked
- [ ] Ready to merge feature branch

**Tested by:** _______________
**Date:** _______________
**Branch:** issue-37-request-builder
**Commit:** _______________

---

## Quick Reference Commands

```bash
# Run full test suite
rake test && rake lint && rake coverage

# Check current branch
git branch

# View recent commits
git log --oneline -10

# Start agent (adjust command as needed)
bin/agent

# Query database
sqlite3 db/memory.db "SELECT * FROM messages ORDER BY id DESC LIMIT 5;"

# Check verbosity setting
# (Method depends on your configuration system)
```

## Verbosity Level Reference

| Level | Content Displayed |
|-------|-------------------|
| 0 | Nothing (silent mode) |
| 1 | Final user message only |
| 2 | + System prompt |
| 3 | + RAG content (if present) |
| 4 | + Tool definitions |
| 5 | + Complete message history |

---

**Note:** This checklist should be reviewed and checked off systematically. Any issues discovered during testing should be documented in the "Issues Found" section and addressed before considering the refactoring complete.
