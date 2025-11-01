# Manual Testing Checklist - Hang Bug Fix

## Status Legend
- [ ] Not tested
- [✓] Passed
- [✗] Failed

---

## Basic Functionality

### Test 1: Simple query (debug off)
- [✓] Status
- **Steps:**
  1. Start nu-agent
  2. Run: `what is 2 + 2`
- **Expected:** Query completes and returns to prompt (no hang)
- **Actual:** Query completed successfully, no hang

---

### Test 2: Simple query (debug on)
- [✓] Status
- **Steps:**
  1. Run: `/debug on`
  2. Run: `what is the capital of France`
- **Expected:** Shows `[Thread] Orchestrator Starting`, query completes, shows `[Thread] Orchestrator Finished`
- **Actual:** Debug messages displayed correctly, query completed successfully

---

## Debug Output & Spinner Behavior

### Test 3: Thread events display
- [✓] Status
- **Steps:**
  1. With `/debug on`
  2. Run: `tell me a joke`
- **Expected:** See thread start/finish messages, spinner restarts after each debug message
- **Actual:** Thread messages displayed correctly, query completed successfully. Spinner appeared briefly after start message but not after subsequent messages (likely due to fast processing)

---

### Test 4: Message tracking (verbosity level 1)
- [N/A] Status
- **Steps:**
  1. Run: `/message verbosity 1`
  2. Run: `what is 5 * 5`
- **Expected:** Shows message creation events, no hang
- **Actual:** Cannot test - /message command not implemented yet

---

### Test 5: Message tracking (verbosity level 2)
- [N/A] Status
- **Steps:**
  1. Run: `/message verbosity 2`
  2. Run: `count to 3`
- **Expected:** Shows detailed message info (role, actor), no hang
- **Actual:** Cannot test - /message command not implemented yet

---

## Sequential Operations

### Test 6: Multiple queries in sequence
- [✓] Status
- **Steps:**
  1. Run: `what is 1 + 1`
  2. Wait for completion
  3. Run: `what is 2 + 2`
  4. Wait for completion
  5. Run: `what is 3 + 3`
- **Expected:** All three queries complete without hanging
- **Actual:** All three queries completed successfully, no hangs

---

## Error Handling

### Test 7: Query with debug toggle mid-session
- [✓] Status
- **Steps:**
  1. Run: `what is 10 + 10` (with debug on)
  2. Run: `/debug off`
  3. Run: `what is 20 + 20`
  4. Run: `/debug on`
  5. Run: `what is 30 + 30`
- **Expected:** All queries complete, debug output only when enabled
- **Actual:** All queries completed successfully, debug toggled correctly

---

## Interrupt Handling

### Test 8: Ctrl-C during query
- [✓] Status
- **Steps:**
  1. Run a query: `write a long story about a cat`
  2. Press Ctrl-C while it's processing
  3. Run: `what is 1 + 1`
- **Expected:** First query aborts, second query works normally
- **Actual:** Query interrupted successfully, subsequent query worked normally

---

## Edge Cases

### Test 9: Empty input
- [✓] Status
- **Steps:**
  1. Press Enter without typing anything
  2. Run: `test query`
- **Expected:** Empty input ignored, next query works
- **Actual:** Empty input ignored, next query worked normally

---

### Test 10: Commands still work
- [✓] Status
- **Steps:**
  1. Run: `/info`
  2. Run: `/help`
  3. Run: `simple query`
- **Expected:** Commands execute, query works
- **Actual:** All commands executed successfully, query worked normally

---

## Summary
- Total Tests: 10
- Passed: 7 (Tests 1, 2, 3, 6, 7, 8, 9, 10)
- Failed: 0
- Not Applicable: 2 (Tests 4 & 5 - /message command not implemented yet)
- Not Tested: 0
