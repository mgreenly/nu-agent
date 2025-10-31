# Manual Test Checklist for Multiline Editing

**Test Date:** ___________
**Tester:** ___________
**Terminal:** ___________ (e.g., Ghostty, iTerm2, gnome-terminal)
**Branch:** issue-22+6-editor

## Pre-Test Setup
- [ ] Build and start application: `bundle exec bin/nu-agent`
- [ ] Verify application starts without errors
- [ ] Note terminal type and environment

---

## Test 1: Basic Multiline Input Creation
**Goal:** Verify Enter inserts newlines and Ctrl+J submits

**Steps:**
1. [ ] Type: `SELECT *` (don't press anything yet)
2. [ ] Press **Enter** (should insert newline, NOT submit)
3. [ ] Verify you see the cursor move to line 2
4. [ ] Type: `FROM users`
5. [ ] Press **Enter** again
6. [ ] Verify cursor on line 3
7. [ ] Type: `WHERE id = 1`
8. [ ] Press **Ctrl+J** to submit
9. [ ] Verify submission occurred (application responds)

**Expected Results:**
- [ ] Three lines displayed as you type
- [ ] Enter creates newlines (does not submit)
- [ ] Ctrl+J submits the complete multiline query
- [ ] Can retrieve from history later

**Observations:**
```


```

---

## Test 2: Navigation with Up/Down Arrows
**Goal:** Verify arrow keys navigate between lines in non-empty buffer

**Steps:**
1. [ ] Type SQL query from Test 1 (3 lines)
2. [ ] Cursor should be at end of line 3
3. [ ] Press **Up Arrow** (should move to line 2)
4. [ ] Press **Up Arrow** again (should move to line 1)
5. [ ] Press **Down Arrow** (should move to line 2)
6. [ ] Press **Ctrl+J** to submit

**Expected Results:**
- [ ] Up/Down arrows navigate between lines (NOT history)
- [ ] Cursor moves to appropriate line
- [ ] Content remains intact
- [ ] Can navigate through all lines

**Observations:**
```


```

---

## Test 3: Column Memory During Navigation
**Goal:** Verify cursor column is remembered when moving between lines of different lengths

**Steps:**
1. [ ] Type: `short` then **Enter**
2. [ ] Type: `this is a longer line here` then **Enter**
3. [ ] Type: `short`
4. [ ] Press **Up Arrow** (to line 2)
5. [ ] Use arrow keys to position cursor at column 10 (the 'e' in "here")
6. [ ] Press **Up Arrow** (goes to line 1 - "short")
7. [ ] Note cursor position (should be at end of "short")
8. [ ] Press **Down Arrow** (returns to line 2)
9. [ ] Note cursor position (should return to column 10)

**Expected Results:**
- [ ] Moving up to shorter line: cursor clamps to end
- [ ] Moving back down: cursor restores to saved column 10
- [ ] Column memory maintained during vertical movement

**Observations:**
```


```

---

## Test 4: Editing Multiline Content
**Goal:** Verify editing works within multiline content

**Steps:**
1. [ ] Type: `line one` then **Enter**
2. [ ] Type: `line two` then **Enter**
3. [ ] Type: `line three`
4. [ ] Press **Up Arrow** twice (to line 1)
5. [ ] Press **Left Arrow** 3 times (position after "line ")
6. [ ] Type: `NUMBER ` (insert text)
7. [ ] Verify line 1 shows: "line NUMBER one"
8. [ ] Press **Down Arrow** (to line 2)
9. [ ] Press **Backspace** 3 times (delete "two")
10. [ ] Type: `2`
11. [ ] Verify line 2 shows: "line 2"

**Expected Results:**
- [ ] Can insert text in middle of lines
- [ ] Can delete text within lines
- [ ] Line 1 becomes: "line NUMBER one"
- [ ] Line 2 becomes: "line 2"
- [ ] Display updates correctly

**Observations:**
```


```

---

## Test 5: History Navigation (Empty Buffer)
**Goal:** Verify history navigation still works with empty buffer

**Steps:**
1. [ ] Submit an entry with **Ctrl+J** (any content)
2. [ ] Press **Ctrl+U** to clear current buffer
3. [ ] Verify buffer is empty
4. [ ] Press **Up Arrow**
5. [ ] Verify previous entry loads

**Expected Results:**
- [ ] Empty buffer allows history navigation (old behavior)
- [ ] Up arrow loads previous history entry
- [ ] Down arrow navigates forward through history

**Observations:**
```


```

---

## Test 6: Multiline History Entry
**Goal:** Verify multiline entries are stored and retrieved from history

**Steps:**
1. [ ] Type a multiline entry (3 lines) and submit with **Ctrl+J**
2. [ ] Clear buffer with **Ctrl+U**
3. [ ] Press **Up Arrow** to load the multiline entry
4. [ ] Verify all 3 lines are displayed
5. [ ] Verify cursor is at end of entry
6. [ ] Try navigating within the loaded multiline entry

**Expected Results:**
- [ ] Full multiline entry loads from history
- [ ] All lines visible
- [ ] Cursor positioned at end
- [ ] Can navigate within loaded entry

**Observations:**
```


```

---

## Test 7: Delete Across Line Boundaries
**Goal:** Verify delete operations work across newlines

**Steps:**
1. [ ] Type: `line1` then **Enter**
2. [ ] Type: `line2`
3. [ ] Press **Up Arrow** (to line 1)
4. [ ] Press **End** or arrow to end of line1
5. [ ] Press **Delete** (forward delete)
6. [ ] Verify result: "line1line2" (newline deleted)

**Expected Results:**
- [ ] Delete removes the newline character
- [ ] Lines are joined together
- [ ] No extra characters inserted

**Observations:**
```


```

---

## Test 8: Ctrl+K (Kill to End)
**Goal:** Verify Ctrl+K kills from cursor to end of buffer

**Steps:**
1. [ ] Type: `first line` then **Enter**
2. [ ] Type: `second line` then **Enter**
3. [ ] Type: `third line`
4. [ ] Press **Up Arrow** twice (to line 1)
5. [ ] Position cursor in middle of "second" (after "sec")
6. [ ] Press **Ctrl+K**
7. [ ] Verify result

**Expected Results:**
- [ ] Everything from cursor to end is deleted
- [ ] Result: `first line\nsec` (kills across lines)
- [ ] Cursor position unchanged

**Observations:**
```


```

---

## Test 9: Ctrl+U (Kill to Start)
**Goal:** Verify Ctrl+U kills from start of buffer to cursor

**Steps:**
1. [ ] Type: `first line` then **Enter**
2. [ ] Type: `second line` then **Enter**
3. [ ] Type: `third line`
4. [ ] Press **Up Arrow** (to line 2)
5. [ ] Position cursor in middle of "second" (after "sec")
6. [ ] Press **Ctrl+U**
7. [ ] Verify result

**Expected Results:**
- [ ] Everything from start to cursor is deleted
- [ ] Result: `ond line\nthird line`
- [ ] Cursor moves to position 0

**Observations:**
```


```

---

## Test 10: Ctrl+Enter Submit (Terminal-specific)
**Goal:** Verify Ctrl+Enter submits (if terminal supports it)

**Steps:**
1. [ ] Type some multiline content
2. [ ] Press **Ctrl+Enter** to submit
3. [ ] Note whether it works

**Expected Results:**
- [ ] Submits in Ghostty/xterm-compatible terminals
- [ ] May not work in all terminals (expected)
- [ ] Ctrl+J always works as fallback

**Observations:**
```


```

---

## Test 11: Empty Lines and Trailing Newlines
**Goal:** Verify handling of empty lines within content

**Steps:**
1. [ ] Type: `first`
2. [ ] Press **Enter** twice (creates empty line)
3. [ ] Type: `third`
4. [ ] Press **Enter** (trailing newline)
5. [ ] Navigate with **Up/Down** arrows
6. [ ] Try to position cursor on empty line 2
7. [ ] Try to position cursor on empty line 4 (after trailing newline)

**Expected Results:**
- [ ] Can navigate through empty lines
- [ ] Empty line 2 is preserved in content
- [ ] Trailing newline creates navigable empty line
- [ ] No crashes or confusion

**Observations:**
```


```

---

## Test 12: Very Long Lines
**Goal:** Verify no issues with very long lines

**Steps:**
1. [ ] Type a very long line (200+ characters - mash keyboard)
2. [ ] Press **Enter**
3. [ ] Type a normal short line
4. [ ] Navigate between them with arrows
5. [ ] Observe display behavior

**Expected Results:**
- [ ] Long line displays (may wrap visually in terminal)
- [ ] Navigation works correctly
- [ ] No crashes
- [ ] No display corruption
- [ ] Can edit long lines

**Observations:**
```


```

---

## Test 13: Left/Right Arrow Across Lines
**Goal:** Verify left/right arrows cross line boundaries

**Steps:**
1. [ ] Type: `line1` then **Enter**
2. [ ] Type: `line2`
3. [ ] Press **Up Arrow** (to line 1)
4. [ ] Press **End** to go to end of line 1
5. [ ] Press **Right Arrow** (should jump to start of line 2)
6. [ ] Press **Left Arrow** (should jump back to end of line 1)

**Expected Results:**
- [ ] Right arrow at end of line moves to start of next line
- [ ] Left arrow at start of line moves to end of previous line
- [ ] Boundary crossing works smoothly

**Observations:**
```


```

---

## Test 14: Home/End Keys
**Goal:** Verify Home/End jump to buffer start/end

**Steps:**
1. [ ] Type multiline content (3 lines)
2. [ ] Position cursor in middle of line 2
3. [ ] Press **Home**
4. [ ] Verify cursor at start of entire buffer (line 1, column 0)
5. [ ] Press **End**
6. [ ] Verify cursor at end of entire buffer (line 3, last position)

**Expected Results:**
- [ ] Home jumps to start of buffer (not start of line)
- [ ] End jumps to end of buffer (not end of line)
- [ ] Behavior matches plan scope

**Observations:**
```


```

---

## Test 15: Quick Smoke Test
**Goal:** Rapid verification of core functionality

**Steps:**
1. [ ] Type: `hello` then **Enter** then `world` then **Ctrl+J**
2. [ ] Verify submission of "hello\nworld"
3. [ ] Press **Up Arrow** to load from history
4. [ ] Verify multiline entry loads
5. [ ] Type: `line1` then **Enter** then `line2` then **Enter** then `line3`
6. [ ] Press **Up Arrow** twice (to line 1)
7. [ ] Type: `EDITED `
8. [ ] Press **Ctrl+J**
9. [ ] Verify edited multiline content submits

**Expected Results:**
- [ ] All basic operations work
- [ ] No crashes
- [ ] Display updates correctly

**Observations:**
```


```

---

## Summary

**Total Tests:** 15
**Passed:** _____
**Failed:** _____
**Skipped:** _____

### Critical Issues Found
```




```

### Minor Issues Found
```




```

### Overall Assessment
- [ ] Ready for merge
- [ ] Needs fixes (see issues above)
- [ ] Needs further investigation

**Additional Notes:**
```




```
