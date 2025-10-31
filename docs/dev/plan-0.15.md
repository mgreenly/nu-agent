Nu-Agent v0.15 Plan: Minimal Multiline Editing Support

Last Updated: 2025-10-29
Target Version: 0.15.0
Plan Status: Draft for review

Index
- High-level motivation
- Scope (in)
- Scope (out, future enhancements)
- Key technical decisions and hints
- Implementation phases
  - Phase 1: Line/column calculation helpers
  - Phase 2: Multiline display rendering
  - Phase 3: Submit key handling
  - Phase 4: Up/Down navigation logic
  - Phase 5: Testing and refinement
- Success criteria
- Risks and mitigations
- Future enhancements
- Notes


High-level motivation
- Enable external editor support (Ctrl-G from issue #6) by providing minimal multiline editing in ConsoleIO.
- When users return from external editor, they need to see and navigate multiline content before submission.
- Avoid complex inline multiline editing features - just enough to display, navigate, and submit editor output.
- Keep the implementation minimal and focused on the external editor use case.

Scope (in)
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

Scope (out, future enhancements)
- Advanced inline multiline editing features (visual line wrapping, line numbers, etc.).
- Syntax highlighting or bracket matching for multiline code.
- Line-aware Home/End keys (jump to start/end of current line instead of buffer).
- Ctrl+Home/Ctrl+End for buffer start/end navigation.
- Alt+arrow word navigation across lines.
- Block selection or visual mode.
- Undo/redo support for complex multiline edits.

Key technical decisions and hints
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

Implementation phases

Phase 1: Line/column calculation helpers (1 hr)
Goal: Add methods to convert between byte offset and (line, column) coordinates.
Tasks
- Add get_lines method: split @input_buffer on "\n" with -1 limit to preserve trailing empty line.
- Add get_line_and_column(pos) method:
  - Iterate through lines, tracking cumulative position.
  - Return [line_index, column_offset] for given byte position.
  - Handle edge cases: empty buffer, position at end, position beyond buffer length.
- Add get_position_from_line_column(line, col) method:
  - Sum lengths of previous lines (each +1 for newline except last).
  - Add column offset, clamped to target line's length.
  - Return byte position.
- Add @saved_column instance variable to track desired column during vertical navigation.
Testing
- Unit tests for position calculations: various buffer contents, edge cases (empty, single line, trailing newline).
- Verify round-trip: pos → (line, col) → pos gives same position.
- Test column clamping when moving to shorter line.

Phase 2: Multiline display rendering (2 hrs)
Goal: Update display methods to render multiple lines and position cursor in 2D.
Tasks
- Add @last_line_count instance variable (initialize to 1).
- Update redraw_input_line(prompt):
  - Calculate lines = get_lines and cursor_line, cursor_col.
  - Move up (@last_line_count - 1) times to first line of previous input.
  - Clear from current position to end of screen (\e[J).
  - Render each line: first line includes prompt, others start with \r\n.
  - Update @last_line_count = lines.length.
  - Position cursor: move up to first line, move down to cursor_line, set column.
- Update clear_screen(prompt):
  - Similar multiline rendering after \e[2J\e[H.
- Update handle_output_for_input_mode(prompt):
  - Clear multiline input area before writing background output.
  - Redraw multiline input after background output.
  - Position cursor correctly.
- Test with empty buffer, single line, multiple lines, lines of varying lengths.
Testing
- Manual testing: type text, press Enter, verify newline displayed correctly.
- Test cursor positioning at various locations in multiline buffer.
- Test background output arrival during multiline editing (doesn't corrupt display).

Phase 3: Submit key handling (30 min)
Goal: Change Enter to insert newline, add submit keys.
Tasks
- Update parse_input method:
  - when "\r" → insert_char("\n") instead of return :submit.
  - when "\n" → return :submit (Ctrl+J).
  - Add Ctrl+Enter detection if possible (terminal-specific, optional).
- Consider: Ctrl+Enter often sends \r with modifiers, but in raw mode this is hard to detect reliably.
- Document that Ctrl+J is the reliable submit key, Ctrl+Enter may work depending on terminal.
Testing
- Test Enter inserts newline (displays on new line).
- Test Ctrl+J submits input (multiline content submitted as single string with embedded \n).
- Test submitted multiline content is added to history correctly.
- Test empty buffer submit (should submit empty string).

Phase 4: Up/Down navigation logic (1 hr)
Goal: Implement smart up/down navigation: history when empty, line navigation when non-empty.
Tasks
- Update handle_csi_sequence for "A" (up) and "B" (down):
  - Call cursor_up_or_history_prev and cursor_down_or_history_next instead of history_prev/next.
- Implement cursor_up_or_history_prev:
  - if @input_buffer.empty? → history_prev (navigate to previous history entry).
  - else: navigate within buffer:
    - Calculate current_line, current_col.
    - if current_line > 0 → move to previous line (save @saved_column, call get_position_from_line_column).
    - else → stay on first line (do nothing, or optionally beep).
- Implement cursor_down_or_history_next:
  - if @input_buffer.empty? → history_next (navigate to next history entry).
  - else: navigate within buffer:
    - Calculate current_line, current_col.
    - if current_line < lines.length - 1 → move to next line.
    - else → stay on last line (do nothing).
- Reset @saved_column on horizontal movement, edits, or history navigation.
- Update insert_char, delete_backward, delete_forward, cursor_forward, cursor_backward, cursor_to_start, cursor_to_end to set @saved_column = nil.
Testing
- Empty buffer: Up/Down navigate history (existing behavior preserved).
- Single line buffer: Up/Down navigate history (since can't move within single line... wait, no - if buffer is non-empty single line, up/down should do nothing).
- Multiline buffer: Up/Down move between lines, maintain column position.
- Edge: pressing Up on first line of multiline buffer does nothing (doesn't jump to history).
- Edge: pressing Down on last line of multiline buffer does nothing.
- Column memory: move from long line to short line to long line preserves original column.

Phase 5: Testing and refinement (1 hr)
Goal: Comprehensive testing and edge case handling.
Tasks
- Manual testing scenarios:
  - Type multiline input using Enter, navigate with arrows, submit with Ctrl+J.
  - Edit multiline input (insert/delete in middle of lines).
  - Load multiline history entry, navigate within it, edit, submit.
  - Background output arrives during multiline editing, verify display.
  - Empty buffer history navigation still works.
  - Ctrl+K, Ctrl+U, Ctrl+W work correctly (may kill across lines).
- Edge cases:
  - Buffer with only newlines: "\n\n\n".
  - Very long lines (handle terminal width limitations if any).
  - Cursor at end of buffer with trailing newline.
  - Rapid input during redraw.
- Refinement:
  - Adjust ANSI sequence logic if display glitches occur.
  - Tune @last_line_count tracking for edge cases.
  - Ensure cursor doesn't jump unexpectedly.
Testing
- Run existing ConsoleIO specs, ensure they still pass.
- Add new specs for multiline scenarios if feasible (may require mocking input).
- Document any known limitations or quirks.

Success criteria
- Functional: Users can type multiline input using Enter, navigate with arrows, and submit with Ctrl+J.
- External editor ready: ConsoleIO can display and allow editing of multiline content returned from external editor (issue #6 unblocked).
- History preserved: Empty buffer navigation still works exactly as before (no regression).
- Display quality: Multiline content renders cleanly, cursor positioned correctly, no visual artifacts.
- Background output: Multiline input doesn't break when background tasks write output.
- Minimal scope: Implementation is simple and focused; no attempt at full-featured multiline editor.

Risks and mitigations
- ANSI sequence complexity: Different terminals may interpret sequences differently; test on common terminals (xterm, gnome-terminal, iTerm2).
- Ctrl+Enter detection: May not work reliably; ensure Ctrl+J is clearly documented as primary submit key.
- Column memory bugs: Off-by-one errors when calculating positions; thorough testing of edge cases.
- Performance: Recalculating line/column on every redraw; optimize if noticeable lag (unlikely for typical input sizes).
- Kill commands across lines: Ctrl+K/Ctrl+U may delete newlines; document this behavior, consider acceptable for minimal implementation.
- Terminal size changes: SIGWINCH not handled; multiline input may break on resize (document as known limitation).
- History confusion: Users may expect up/down to always navigate history; document new behavior clearly.

Future enhancements
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

Notes
- This implementation prioritizes simplicity over feature completeness; goal is to unblock external editor support, not to build a full multiline editor.
- Users who need complex multiline editing should use the external editor (Ctrl-G); ConsoleIO multiline is for display and minor tweaks.
- The "empty buffer for history" rule is simple and predictable; users can clear buffer (Ctrl+U) to access history if needed.
- Column memory behavior matches expectations from Vim, Emacs, and most terminal editors.
- Multiline history entries become first-class: navigate within them, edit them, learn from them.
- Implementation builds on existing ConsoleIO architecture; no major refactoring needed.

Example usage:
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

External editor integration (future, issue #6):
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
