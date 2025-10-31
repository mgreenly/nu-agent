Nu-Agent Plan: Minimal Multiline Editing Support

Last Updated: 2025-10-31
Plan Status: Active implementation
Progress: Not started

## Index
- Development process requirements
- High-level motivation
- Scope (in)
- Scope (out, future enhancements)
- Key technical decisions and hints
- Implementation phases
  - Phase 1: Line/column calculation helpers
  - Phase 2: Multiline display rendering
  - Phase 3: Submit key handling
  - Phase 4: Up/Down navigation logic
  - Phase 5: Integration testing and edge cases
- Success criteria
- Risks and mitigations
- Future enhancements
- Notes

## Development Process Requirements

**CRITICAL:** Every task MUST follow this workflow:

### TDD Red/Green Cycle
1. **RED**: Write failing test first (verifies test actually tests something)
2. **GREEN**: Write minimal code to make test pass
3. **REFACTOR**: Clean up code while keeping tests green

### Quality Gates (After Every Task)
After completing each task, you MUST verify:
```bash
# Run all three commands and ensure they ALL pass:
bundle exec rake spec              # All tests pass
bundle exec rake rubocop           # No lint violations
bundle exec rake spec COVERAGE_ENFORCE=true  # Coverage thresholds met
```

### Coverage Requirements
- **Line coverage**: Must be ≥ 98.16% (0.01% margin over 98.15% requirement)
- **Branch coverage**: Must be ≥ 90.01% (0.01% margin over 90.00% requirement)
- Current baseline: 98.17% line / 90.02% branch
- **Never let coverage drop below these thresholds**

### Git Workflow
1. Make one commit per completed task
2. Commit message format: `[Phase X.Y] Brief description of task`
3. Update this plan document's progress section after every task
4. Mark task as ✅ DONE with completion timestamp

### Progress Tracking Format
Each task must be tracked as:
- ⏳ IN PROGRESS - Currently working on this task
- ✅ DONE (YYYY-MM-DD HH:MM) - Completed and committed
- ⏸️ BLOCKED - Cannot proceed (note blocker)
- ⏭️ SKIPPED - Explicitly skipped (note reason)

## High-level motivation
- Enable external editor support (Ctrl-G from issue #6) by providing minimal multiline editing in ConsoleIO.
- When users return from external editor, they need to see and navigate multiline content before submission.
- Avoid complex inline multiline editing features - just enough to display, navigate, and submit editor output.
- Keep the implementation minimal and focused on the external editor use case.

## Scope (in)
- Display multiple lines of input with proper cursor positioning in 2D space (line + column).
- Enter key inserts newline character for multiline input.
- Ctrl+J and Ctrl+Enter both submit input (Ctrl+J is reliable fallback).
- Up/Down arrow navigation:
  - Empty buffer: navigate command history (current behavior).
  - Non-empty buffer: navigate between lines within the buffer.
- Column memory when moving up/down between lines (similar to Vim/Emacs behavior).
- Proper redrawing when background output arrives during multiline editing.
- Left/Right arrows work across line boundaries (existing behavior continues).
- Home/End jump to start/end of entire buffer (no change from current behavior).

## Scope (out, future enhancements)
- Advanced inline multiline editing features (visual line wrapping, line numbers, etc.).
- Syntax highlighting or bracket matching for multiline code.
- Line-aware Home/End keys (jump to start/end of current line instead of buffer).
- Ctrl+Home/Ctrl+End for buffer start/end navigation.
- Alt+arrow word navigation across lines.
- Block selection or visual mode.
- Undo/redo support for complex multiline edits.

## Key technical decisions and hints
- Buffer representation: Continue using single @input_buffer string with embedded "\n" characters for newlines.
- Position tracking: @cursor_pos remains byte offset into buffer; calculate line/column on demand for rendering.
- Submit detection:
  - Enter key (\r) → insert "\n" character into buffer.
  - Ctrl+J (\n) → submit input (reliable across all terminals).
  - Ctrl+Enter → attempt to detect terminal-specific sequences, fall back to Ctrl+J.
- Navigation logic: Single check at start of up/down handler: "if @input_buffer.empty? then history_navigation else line_navigation".
- Column memory: Track @saved_column when moving vertically; reset on horizontal movement or edits.
- Multiline display:
  - Track @last_line_count to know how many lines to clear on redraw.
  - Use ANSI sequences: \e[A (up), \e[B (down), \e[J (clear to end), \e[G (column position).
  - Render prompt only on first line; subsequent lines start at column 1.
- Cursor positioning: Calculate (line, column) from @cursor_pos, then use ANSI to move cursor to correct screen position.
- History integration: When loading multiline history entry, display all lines and allow navigation within it.

## Implementation phases

### Phase 1: Line/column calculation helpers
**Status**: Not started
**Goal**: Add methods to convert between byte offset and (line, column) coordinates.
**File**: `lib/nu/agent/console_io.rb`

#### Task 1.1: Add lines method ✅ DONE (2025-10-31 15:01)
**TDD Steps**: ✅ COMPLETED
1. ✅ Write spec test for `lines` with empty buffer → expect `[""]`
2. ✅ Write spec test for single line "hello" → expect `["hello"]`
3. ✅ Write spec test for "line1\nline2" → expect `["line1", "line2"]`
4. ✅ Write spec test for trailing newline "line1\n" → expect `["line1", ""]`
5. ✅ Implement `lines` method with special case for empty buffer
6. ✅ Run tests until green
7. ✅ Run lint, fix naming issue (get_lines → lines)
8. ✅ Run coverage check - thresholds met
9. ✅ Commit: `[Phase 1.1] Add lines method for splitting buffer into lines`
10. ✅ Update this document with ✅ DONE timestamp

**Acceptance criteria**: ✅ ALL MET
- ✅ `split("\n", -1)` preserves trailing empty line
- ✅ Special case for empty buffer returns `[""]`
- ✅ All edge cases tested (empty, single line, multiline, trailing newline)
- ✅ Tests pass, lint passes, coverage maintained (98.17% line, 90.02% branch)

#### Task 1.2: Add get_line_and_column(pos) method ✅ DONE (2025-10-31 15:10)
**TDD Steps**: ✅ COMPLETED
1. ✅ Write spec: empty buffer, pos=0 → expect `[0, 0]`
2. ✅ Write spec: "hello", pos=3 → expect `[0, 3]`
3. ✅ Write spec: "line1\nline2", pos=6 → expect `[1, 0]` (first char of line2)
4. ✅ Write spec: "line1\nline2", pos=8 → expect `[1, 2]`
5. ✅ Write spec: pos beyond buffer length → expect clamping to last valid position
6. ✅ Write spec: additional edge cases (trailing newline, empty lines, etc.)
7. ✅ Implement method: iterate through lines, track cumulative position
8. ✅ Run tests until green
9. ✅ Refactor comments for clarity
10. ✅ Run lint, fix any issues
11. ✅ Run coverage check - thresholds met (98.16% line / 90.07% branch)
12. ✅ Commit: `[Phase 1.2] Add get_line_and_column position calculation method`
13. ✅ Update this document with ✅ DONE timestamp

**Acceptance criteria**: ✅ ALL MET
- ✅ Returns [line_index, column_offset] as integers
- ✅ Handles all edge cases correctly (11 test cases)
- ✅ Properly clamps position to buffer length
- ✅ All quality gates pass (tests, lint, coverage)

#### Task 1.3: Add get_position_from_line_column(line, col) method ✅ DONE (2025-10-31 15:21)
**TDD Steps**: ✅ COMPLETED
1. ✅ Write spec: line=0, col=0 on "hello" → expect `0`
2. ✅ Write spec: line=0, col=3 on "hello" → expect `3`
3. ✅ Write spec: line=1, col=0 on "line1\nline2" → expect `6`
4. ✅ Write spec: line=1, col=5 on "line1\nline2" → expect `11`
5. ✅ Write spec: col beyond line length → expect clamping to line end
6. ✅ Write spec: verify round-trip with get_line_and_column
7. ✅ Implement method: sum line lengths + newlines, add column offset
8. ✅ Run tests until green (10 specs pass)
9. ✅ Refactor: fixed RuboCop issues (used clamp instead of nested min/max)
10. ✅ Run lint: no offenses detected
11. ✅ Run coverage check: 98.16% line / 90.07% branch (thresholds met)
12. ✅ Commit: `[Phase 1.3] Add get_position_from_line_column method`
13. ✅ Update this document with ✅ DONE timestamp

**Acceptance criteria**: ✅ ALL MET
- ✅ Returns byte position as integer
- ✅ Clamps column to target line's length
- ✅ Round-trip test: pos → (line, col) → pos yields same position (verified with 6 test positions)
- ✅ All quality gates pass (tests, lint, coverage)

#### Task 1.4: Add @saved_column instance variable ✅ DONE (2025-10-31 15:30)
**TDD Steps**: ✅ COMPLETED
1. ✅ Write spec: initialize ConsoleIO → expect `@saved_column` is nil
2. ✅ Update initialize method to set `@saved_column = nil`
3. ✅ Run tests until green (2164 examples, 0 failures)
4. ✅ Run lint (no offenses detected)
5. ✅ Run coverage check (98.16% line / 90.07% branch)
6. ✅ Commit: `[Phase 1.4] Add @saved_column instance variable for vertical navigation`
7. ✅ Update this document with ✅ DONE timestamp

**Acceptance criteria**: ✅ ALL MET
- ✅ Variable initialized in `initialize` method
- ✅ Default value is nil
- ✅ Tests verify initialization
- ✅ All quality gates pass

### Phase 2: Multiline display rendering
**Status**: Not started
**Goal**: Update display methods to render multiple lines and position cursor in 2D.
**Files**: `lib/nu/agent/console_io.rb`

#### Task 2.1: Add @last_line_count instance variable ✅ DONE (2025-10-31 15:37)
**TDD Steps**: ✅ COMPLETED
1. ✅ Write spec: initialize ConsoleIO → expect `@last_line_count` equals 1
2. ✅ Update initialize method to set `@last_line_count = 1`
3. ✅ Run tests until green (2164 examples, 0 failures)
4. ✅ Run lint (no offenses detected)
5. ✅ Run coverage check (98.16% line / 90.07% branch)
6. ✅ Commit: `[Phase 2.1] Add @last_line_count instance variable for display tracking`
7. ✅ Update this document with ✅ DONE timestamp

**Acceptance criteria**: ✅ ALL MET
- ✅ Variable initialized to 1 (single line default)
- ✅ Tests verify initialization
- ✅ All quality gates pass

#### Task 2.2: Update redraw_input_line for multiline rendering ✅ DONE (2025-10-31 15:47)
**TDD Steps**: ✅ COMPLETED
1. ✅ Write spec: single line input → expect prompt + text on one line
2. ✅ Write spec: two line input "line1\nline2" → expect two lines displayed
3. ✅ Write spec: verify cursor positioning after multiline render
4. ✅ Write spec: verify @last_line_count updated correctly
5. ✅ Implement multiline rendering logic:
   - Get lines using lines method
   - Calculate cursor position using get_line_and_column
   - Move up (@last_line_count - 1) times when @last_line_count > 1
   - Clear to end of screen with \e[J
   - Render each line (first with prompt, others with \r\n)
   - Update @last_line_count
   - Position cursor at correct line/column (move up from bottom, then set column)
6. ✅ Run tests until green (11 new specs, all pass)
7. ✅ Refactor: RuboCop auto-corrected to use modifier if and move @stdout.write(line) outside conditional
8. ✅ Run lint: no offenses
9. ✅ Run coverage check: 98.17% line / 90.12% branch (thresholds met)
10. ✅ Commit: `[Phase 2.2] Update redraw_input_line for multiline rendering`
11. ✅ Update this document with ✅ DONE timestamp

**Acceptance criteria**: ✅ ALL MET
- ✅ Single line input still works (no regression)
- ✅ Multiline input displays all lines correctly
- ✅ Cursor positioned at correct 2D location (tested with various scenarios)
- ✅ @last_line_count tracks current line count
- ✅ All quality gates pass (2174 examples, 0 failures)

#### Task 2.3: Update clear_screen for multiline support ✅ DONE (2025-10-31 16:00)
**TDD Steps**: ✅ COMPLETED
1. ✅ Write spec: clear_screen with multiline buffer → expect all lines rendered
2. ✅ Write spec: verify cursor positioning in multiline content
3. ✅ Implement multiline rendering after \e[2J\e[H
4. ✅ Run tests until green (5 specs pass, including 3 new multiline tests)
5. ✅ Run lint (no offenses detected)
6. ✅ Run coverage check (98.17% line / 90.15% branch)
7. ✅ Commit: `[Phase 2.3] Update clear_screen for multiline support`
8. ✅ Update this document with ✅ DONE timestamp

**Acceptance criteria**: ✅ ALL MET
- ✅ Screen clears and redisplays multiline input correctly
- ✅ Tests verify multiline rendering (single line, multiline, cursor positioning)
- ✅ All quality gates pass (2177 examples, 0 failures)

#### Task 2.4: Update handle_output_for_input_mode for multiline ✅ DONE (2025-10-31 16:08)
**TDD Steps**: ✅ COMPLETED
1. ✅ Write spec: background output during multiline editing → verify clean redraw
2. ✅ Update method to clear multiline area before output, redraw after
3. ✅ Refactor: Extract do_redraw_input_line private method to avoid mutex deadlock
4. ✅ Run tests until green (2180 examples, 0 failures)
5. ✅ Run lint (no offenses detected)
6. ✅ Run coverage check (98.17% line / 90.16% branch)
7. ✅ Commit: `[Phase 2.4] Update handle_output_for_input_mode for multiline support`
8. ✅ Update this document with ✅ DONE timestamp

**Acceptance criteria**: ✅ ALL MET
- ✅ Background output doesn't corrupt multiline display
- ✅ Input area properly cleared and redrawn (moves up, clears to end of screen)
- ✅ Cursor repositioned correctly via do_redraw_input_line
- ✅ All quality gates pass (tests, lint, coverage)

### Phase 3: Submit key handling
**Status**: Not started
**Goal**: Change Enter to insert newline, add submit keys.
**File**: `lib/nu/agent/console_io.rb`

#### Task 3.1: Update parse_input to make Enter insert newline ✅ DONE (2025-10-31 16:21)
**TDD Steps**: ✅ COMPLETED
1. ✅ Write spec: pressing Enter (\r) → expect :newline action (not :submit)
2. ✅ Write spec: verify \n character inserted into buffer
3. ✅ Update parse_input: when "\r" → call insert_char("\n")
4. ✅ Run tests until green (2183 examples, 0 failures)
5. ✅ Run lint, fix any issues (no offenses detected)
6. ✅ Run coverage check (98.17% line / 90.17% branch)
7. ✅ Commit: `[Phase 3.1] Change Enter key to insert newline instead of submit`
8. ✅ Update this document with ✅ DONE timestamp

**Acceptance criteria**: ✅ ALL MET
- ✅ Enter (\r) inserts newline character
- ✅ Does NOT return :submit
- ✅ Existing single-line tests updated to use new submit key (Ctrl+J)
- ✅ All quality gates pass (tests, lint, coverage)

#### Task 3.2: Make Ctrl+J submit input ✅ DONE (2025-10-31 16:29)
**TDD Steps**: ✅ COMPLETED
1. ✅ Write spec: pressing Ctrl+J (\n) → expect :submit action
2. ✅ Write spec: multiline content submitted with embedded \n characters
3. ✅ Update parse_input: when "\n" → return :submit (already implemented in Task 3.1)
4. ✅ Run tests until green (2186 examples, 0 failures)
5. ✅ Run lint, fix any issues (no offenses detected)
6. ✅ Run coverage check (98.17% line / 90.17% branch)
7. ✅ Commit: `[Phase 3.2] Make Ctrl+J submit multiline input`
8. ✅ Update this document with ✅ DONE timestamp

**Acceptance criteria**: ✅ ALL MET
- ✅ Ctrl+J (\n) returns :submit
- ✅ Multiline content preserved in submission
- ✅ Empty buffer can be submitted
- ✅ All quality gates pass

#### Task 3.3: Add Ctrl+Enter detection (optional) ⏳
**TDD Steps**:
1. Research terminal-specific sequences for Ctrl+Enter
2. If feasible, write spec and implement
3. If not feasible, document as future enhancement
4. Run tests until green
5. Run lint, fix any issues
6. Run coverage check
7. Commit: `[Phase 3.3] Add Ctrl+Enter detection (if feasible)` OR skip with documentation
8. Update this document with ✅ DONE or ⏭️ SKIPPED timestamp

**Acceptance criteria**:
- Either working Ctrl+Enter detection OR documented as unsupported
- All quality gates pass

### Phase 4: Up/Down navigation logic
**Status**: Not started
**Goal**: Implement smart up/down navigation: history when empty, line navigation when non-empty.
**File**: `lib/nu/agent/console_io.rb`

#### Task 4.1: Implement cursor_up_or_history_prev ⏳
**TDD Steps**:
1. Write spec: empty buffer + up arrow → expect history navigation
2. Write spec: single line buffer + up arrow → expect no movement
3. Write spec: multiline buffer, cursor on line 1 + up → expect move to line 0
4. Write spec: multiline buffer, cursor on line 0 + up → expect no movement
5. Write spec: verify @saved_column behavior
6. Implement cursor_up_or_history_prev method
7. Run tests until green
8. Refactor if needed
9. Run lint, fix any issues
10. Run coverage check
11. Commit: `[Phase 4.1] Implement cursor_up_or_history_prev navigation`
12. Update this document with ✅ DONE timestamp

**Acceptance criteria**:
- Empty buffer navigates history (existing behavior)
- Non-empty buffer navigates between lines
- Column memory maintained via @saved_column
- All quality gates pass

#### Task 4.2: Implement cursor_down_or_history_next ⏳
**TDD Steps**:
1. Write spec: empty buffer + down arrow → expect history navigation
2. Write spec: single line buffer + down arrow → expect no movement
3. Write spec: multiline buffer, cursor on line 0 + down → expect move to line 1
4. Write spec: multiline buffer, cursor on last line + down → expect no movement
5. Write spec: verify @saved_column behavior
6. Implement cursor_down_or_history_next method
7. Run tests until green
8. Refactor if needed
9. Run lint, fix any issues
10. Run coverage check
11. Commit: `[Phase 4.2] Implement cursor_down_or_history_next navigation`
12. Update this document with ✅ DONE timestamp

**Acceptance criteria**:
- Empty buffer navigates history (existing behavior)
- Non-empty buffer navigates between lines
- Column memory maintained via @saved_column
- All quality gates pass

#### Task 4.3: Update handle_csi_sequence to use new navigation methods ⏳
**TDD Steps**:
1. Write spec: "A" sequence → calls cursor_up_or_history_prev
2. Write spec: "B" sequence → calls cursor_down_or_history_next
3. Update handle_csi_sequence for "A" and "B" cases
4. Run tests until green
5. Run lint, fix any issues
6. Run coverage check
7. Commit: `[Phase 4.3] Wire up new navigation methods to CSI sequences`
8. Update this document with ✅ DONE timestamp

**Acceptance criteria**:
- Arrow keys use new smart navigation
- Existing behavior preserved for empty buffer
- All quality gates pass

#### Task 4.4: Reset @saved_column on horizontal movement and edits ⏳
**TDD Steps**:
1. Write spec: cursor_forward → expect @saved_column = nil
2. Write spec: cursor_backward → expect @saved_column = nil
3. Write spec: insert_char → expect @saved_column = nil
4. Write spec: delete_backward → expect @saved_column = nil
5. Write spec: delete_forward → expect @saved_column = nil
6. Write spec: cursor_to_start → expect @saved_column = nil
7. Write spec: cursor_to_end → expect @saved_column = nil
8. Update all relevant methods to set @saved_column = nil
9. Run tests until green
10. Run lint, fix any issues
11. Run coverage check
12. Commit: `[Phase 4.4] Reset saved column on horizontal movement and edits`
13. Update this document with ✅ DONE timestamp

**Acceptance criteria**:
- All horizontal movements reset @saved_column
- All edit operations reset @saved_column
- Column memory only preserved during vertical navigation
- All quality gates pass

### Phase 5: Integration testing and edge cases
**Status**: Not started
**Goal**: Comprehensive testing and edge case handling.
**Files**: `spec/nu/agent/console_io_spec.rb`, `lib/nu/agent/console_io.rb`

#### Task 5.1: Add integration tests for multiline workflows ⏳
**TDD Steps**:
1. Write spec: type multiline input using Enter, navigate, submit with Ctrl+J
2. Write spec: edit multiline input (insert/delete in middle of lines)
3. Write spec: load multiline history entry, navigate within it
4. Write spec: background output arrives during multiline editing
5. Run tests until green
6. Run lint, fix any issues
7. Run coverage check
8. Commit: `[Phase 5.1] Add integration tests for multiline workflows`
9. Update this document with ✅ DONE timestamp

**Acceptance criteria**:
- Full user workflows tested end-to-end
- All integration tests pass
- All quality gates pass

#### Task 5.2: Add edge case tests ⏳
**TDD Steps**:
1. Write spec: buffer with only newlines "\n\n\n"
2. Write spec: very long lines (test no terminal width issues)
3. Write spec: cursor at end of buffer with trailing newline
4. Write spec: Ctrl+K across line boundaries
5. Write spec: Ctrl+U across line boundaries
6. Implement fixes for any failures
7. Run tests until green
8. Run lint, fix any issues
9. Run coverage check
10. Commit: `[Phase 5.2] Add edge case tests and fixes`
11. Update this document with ✅ DONE timestamp

**Acceptance criteria**:
- All edge cases handled gracefully
- No crashes or display corruption
- All quality gates pass

#### Task 5.3: Verify no regressions in existing tests ⏳
**TDD Steps**:
1. Run full test suite: `bundle exec rake spec`
2. Verify all existing tests still pass
3. Update any tests that need adjustments for new behavior
4. Run tests until all green
5. Run lint, fix any issues
6. Run coverage check
7. Commit: `[Phase 5.3] Ensure no regressions in existing functionality`
8. Update this document with ✅ DONE timestamp

**Acceptance criteria**:
- 100% of existing tests pass or are intentionally updated
- No unintended regressions
- All quality gates pass

#### Task 5.4: Manual testing and documentation ⏳
**TDD Steps**:
1. Manual test: type multiline input, verify display
2. Manual test: navigate with arrows, verify cursor positioning
3. Manual test: submit with Ctrl+J, verify content preserved
4. Manual test: background output, verify clean redraw
5. Document any known limitations in plan notes
6. Run lint, fix any issues
7. Commit: `[Phase 5.4] Complete manual testing and update documentation`
8. Update this document with ✅ DONE timestamp

**Acceptance criteria**:
- Manual testing confirms all features work
- Any limitations documented
- Plan document updated with final notes

## Success criteria
- ✅ All tasks completed with passing tests, lint, and coverage
- ✅ Functional: Users can type multiline input using Enter, navigate with arrows, and submit with Ctrl+J
- ✅ External editor ready: ConsoleIO can display and allow editing of multiline content (issue #6 unblocked)
- ✅ History preserved: Empty buffer navigation still works exactly as before (no regression)
- ✅ Display quality: Multiline content renders cleanly, cursor positioned correctly, no visual artifacts
- ✅ Background output: Multiline input doesn't break when background tasks write output
- ✅ Minimal scope: Implementation is simple and focused; no attempt at full-featured multiline editor
- ✅ Coverage maintained: Line ≥ 98.16%, Branch ≥ 90.01%
- ✅ All commits follow format and include plan updates

## Risks and mitigations
- ANSI sequence complexity: Different terminals may interpret sequences differently; test on common terminals (xterm, gnome-terminal, iTerm2).
- Ctrl+Enter detection: May not work reliably; ensure Ctrl+J is clearly documented as primary submit key.
- Column memory bugs: Off-by-one errors when calculating positions; thorough testing of edge cases.
- Performance: Recalculating line/column on every redraw; optimize if noticeable lag (unlikely for typical input sizes).
- Kill commands across lines: Ctrl+K/Ctrl+U may delete newlines; document this behavior, consider acceptable for minimal implementation.
- Terminal size changes: SIGWINCH not handled; multiline input may break on resize (document as known limitation).
- History confusion: Users may expect up/down to always navigate history; document new behavior clearly.

## Future enhancements
- Line-aware Home/End: Jump to start/end of current line instead of entire buffer.
- Ctrl+Home/Ctrl+End: Jump to start/end of buffer (when Home/End become line-aware).
- Alt+arrow word navigation: Move by words even across line boundaries.
- Page Up/Page Down: Move by larger increments in tall multiline input.
- Visual line indicators: Show line numbers or continuation markers.
- Syntax highlighting: Detect code blocks and apply basic highlighting.
- Soft wrap: Wrap long lines at terminal width instead of scrolling horizontally.
- Undo/redo: Track edit history for complex multiline sessions.
- Hybrid navigation: Alt+Up/Alt+Down for history even when buffer is non-empty.
- Block editing: Select rectangular regions, edit multiple lines simultaneously.

## Notes
- This implementation prioritizes simplicity over feature completeness; goal is to unblock external editor support, not to build a full multiline editor.
- Users who need complex multiline editing should use the external editor (Ctrl-G); ConsoleIO multiline is for display and minor tweaks.
- The "empty buffer for history" rule is simple and predictable; users can clear buffer (Ctrl+U) to access history if needed.
- Column memory behavior matches expectations from Vim, Emacs, and most terminal editors.
- Multiline history entries become first-class: navigate within them, edit them, learn from them.
- Implementation builds on existing ConsoleIO architecture; no major refactoring needed.

## Example usage
```
# User types:
> SELECT *<Enter>
FROM users<Enter>
WHERE id = 1<Ctrl+J>

# Display shows:
> SELECT *
FROM users
WHERE id = 1

# Cursor can be on any line, Left/Right move horizontally, Up/Down move vertically.
# Ctrl+J submits entire content as single command with embedded newlines.
# History stores it as single multiline entry; retrieving it shows all lines.
```

## External editor integration (future, issue #6)
```
# User presses Ctrl-G with empty or partial input:
> SELECT *<Ctrl-G>

# ConsoleIO:
# 1. Exits raw mode, writes @input_buffer to tempfile.
# 2. Launches $EDITOR on tempfile.
# 3. User edits in full editor (Vim/Emacs/Nano).
# 4. On editor exit, reads tempfile content into @input_buffer.
# 5. Re-enters raw mode, displays multiline content.
# 6. User can navigate/edit with new multiline support, submit with Ctrl+J.
```

## Task Completion Log
<!-- Update this section as you complete tasks -->

### Phase 1: Line/column calculation helpers
- Task 1.1: Add lines method - ✅ DONE (2025-10-31 15:01)
- Task 1.2: Add get_line_and_column(pos) method - ✅ DONE (2025-10-31 15:10)
- Task 1.3: Add get_position_from_line_column(line, col) method - ✅ DONE (2025-10-31 15:21)
- Task 1.4: Add @saved_column instance variable - ✅ DONE (2025-10-31 15:30)

### Phase 2: Multiline display rendering
- Task 2.1: Add @last_line_count instance variable - ✅ DONE (2025-10-31 15:37)
- Task 2.2: Update redraw_input_line for multiline rendering - ✅ DONE (2025-10-31 15:47)
- Task 2.3: Update clear_screen for multiline support - ✅ DONE (2025-10-31 16:00)
- Task 2.4: Update handle_output_for_input_mode for multiline - ✅ DONE (2025-10-31 16:08)

### Phase 3: Submit key handling
- Task 3.1: Update parse_input to make Enter insert newline - ✅ DONE (2025-10-31 16:21)
- Task 3.2: Make Ctrl+J submit input - ✅ DONE (2025-10-31 16:29)
- Task 3.3: Add Ctrl+Enter detection (optional) - ⏳

### Phase 4: Up/Down navigation logic
- Task 4.1: Implement cursor_up_or_history_prev - ⏳
- Task 4.2: Implement cursor_down_or_history_next - ⏳
- Task 4.3: Update handle_csi_sequence to use new navigation methods - ⏳
- Task 4.4: Reset @saved_column on horizontal movement and edits - ⏳

### Phase 5: Integration testing and edge cases
- Task 5.1: Add integration tests for multiline workflows - ⏳
- Task 5.2: Add edge case tests - ⏳
- Task 5.3: Verify no regressions in existing tests - ⏳
- Task 5.4: Manual testing and documentation - ⏳
