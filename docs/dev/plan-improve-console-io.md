ConsoleIO improvement plan and review

Overall assessment
- Strong design: Clear state machine separation (Idle, ReadingUserInput, StreamingAssistant, Progress, Paused) keeps behavior predictable and simplifies invariants. The output queue + pipe signaling and a single mutex for screen mutations are solid choices for concurrency-safe terminal updates.
- Practical terminal control: Raw mode, IO.select multiplexing, and careful redraw logic for multiline input are thoughtfully implemented. Progress and spinner behaviors are straightforward and usable.
- Encapsulation: SpinnerState is a nice touch; database-backed history is optional and non-fatal on failure.

High-priority issues and fixes
1) Ctrl-D/EOF handling bug
- Issue: parse_input never returns :eof, so handle_eof is unreachable. Ctrl-D maps to delete_forward always; EOF from read_nonblock may raise EOFError and crash the app.
- Fix: In parse_input, treat Ctrl-D as EOF when @input_buffer.empty? and return :eof. In handle_stdin_input, rescue EOFError and return handle_eof.

2) Window resizing not handled
- Issue: @terminal_width is captured once at init. Wrapped line calculations and cursor placement will be wrong after a resize.
- Fix: Track a @winch_pending flag via Signal.trap("WINCH") { @winch_pending = true }. At safe points in readline/spinner loops, if @winch_pending, refresh @terminal_width = IO.console.winsize[1] and redraw.

3) Unicode grapheme width and tabs
- Issue: physical row math uses String#length, which is not display width. Combining characters, East Asian wide characters, emoji, and tabs will misplace the cursor and wrapping.
- Fix: Use a display width function (e.g., unicode-display_width gem or a wcwidth implementation). Normalize tabs (expand to spaces at 8 columns or a configured width) in display calculations.

4) Thread safety of spinner state and shutdown
- Issue: @spinner_state is read/written from multiple threads without synchronization; at_exit only restores terminal, not spinner shutdown or pipe close. Thread#raise on parent is dangerous.
- Fix: Protect @spinner_state fields with the existing @mutex or a dedicated mutex. In at_exit/close: stop spinner, join thread, close @output_pipe_read/write, then restore terminal. Prefer cooperative cancellation over Thread#raise: set an interrupt flag and let the calling code poll interrupt_requested? or wait on a cancellation primitive.

5) Non-TTY and portability
- Issue: Blindly calls stty -g and raw!; Windows or non-interactive environments may break. Spinner frames are Unicode and may not render on Windows terminals.
- Fix: Check @stdin.tty? and @stdout.tty?. If not TTY, skip raw mode and fall back to simple blocking gets/puts without escape codes, disable spinner/progress or use simple text. Gate stty calls; use IO.console only when available. Provide ASCII spinner fallback and color detection.

6) Output when idle
- Issue: Output queue is drained only during readline or spinner loops. If code calls console.puts while idle (no input and no spinner), output may sit in the queue until the next interaction.
- Fix: Add a lightweight background flusher thread that blocks on @output_pipe_read and flushes output even in Idle. Or drain immediately in puts when in Idle state with no active editor/spinner, guarded by the mutex.

Medium-priority improvements
- API for streaming without newline
  - Current handle_output_for_* always appends CRLF, so token streaming becomes one line per chunk. Add print(text) that does not append newline and a flush_line to terminate. Alternatively, auto-detect trailing newline.

- Bracketed paste mode
  - Enable bracketed paste to avoid interpreting escape sequences inside pasted content and to treat paste as a single insertion. Toggle on entering readline and off on exit.

- CSI parsing completeness
  - The escape handling covers common arrows, home/end variants, and delete. Consider handling modifiers (e.g., Alt/Option arrows like CSI 1;3D), word-wise navigation (Alt-B/F), and PageUp/PageDown for history paging.

- History behavior
  - Add a configurable max in-memory history length; dedupe beyond the last-entry-only rule (e.g., dedupe last N). Consider per-line vs. block history for multiline entries.

- Cursor visibility and UX polish
  - Hide cursor during spinner/progress rendering and restore on exit. Debounce spinner redraws on rapid message updates.

- Error handling and logging
  - log_state_transition currently uses puts; during Idle with no flusher it may delay. Route debug to a direct write method that bypasses the queue or ensure flusher exists. Also guard ANSI color use based on capability.

- Rename puts
  - Instance method name puts can be confused with Kernel#puts and can lead to accidental global calls. Consider out, print_line, or write_line to reduce ambiguity.

- Resource management
  - Ensure close can be called idempotently; close pipes and nil them; guard all write paths against closed pipes. Ensure spinner loop exits promptly if pipes close.

- Refactor shared output draining
  - handle_output_for_input_mode and handle_output_for_spinner_mode largely duplicate logic. Extract a unified drain_and_write_output method parameterized by how to redraw tail (input or spinner).

Nice-to-haves
- Optional reliance on Reline/Readline
  - If concurrency-safe redraw with background output is achievable, integrating Reline could reduce maintenance for line editing, history, and Unicode handling.

- Word semantics
  - kill_word_backward uses whitespace boundaries. Consider shell-like word characters (alnum + underscore) and punctuation-aware deletes.

- Tab completion hook
  - Provide a callback API for completions and hints, since the editor already manages the buffer and cursor.

- Rate limiting/backpressure on output_queue
  - Prevent unbounded growth under heavy background output; offer a max size and drop or coalesce lines with a warning indicator.

Testing recommendations
- Correctness
  - Ctrl-D at empty vs non-empty buffer, EOF from read_nonblock, Ctrl-C during spinner and during input, history transitions, multiline wrapping calculations over varying prompt lengths.

- Unicode/display width
  - Wide characters, combining marks, emoji, mixed-width strings, and tabs; verify cursor placement and wrapping calculations.

- Resize
  - SIGWINCH handling with interactive redraw across multiple line counts and cursor positions.

- Concurrency
  - Flood output queue while editing; ensure no interleaving or cursor corruption. Spinner output mixed with background puts.

- Portability
  - Non-TTY mode behavior; Windows or CI shells; color-capable and non-color terminals.

Next actions
- Implement EOF handling fix and add tests for Ctrl-D and EOFError paths.
- Add SIGWINCH handling and a redraw path; create tests that simulate width changes.
- Introduce a display width helper (unicode-display_width or wcwidth) and update wrapping/cursor math; add Unicode test cases.
- Add synchronized spinner state and a clean shutdown path; remove Thread#raise usage for interrupts.
- Add idle output flusher or immediate idle drain; add tests for idle output emissions.
- Introduce print/flush_line API; adapt streaming code paths.
- Add bracketed paste mode in readline flow; test with paste-heavy inputs.
- Make non-TTY fallback path and Windows-friendly spinner frames; exercise in CI.

Summary
The implementation is thoughtfully structured and works well for the common TTY case with simple ASCII input. Addressing EOF handling, window resizing, Unicode width, and shutdown/thread-safety will make it robust. Adding a background flusher or immediate Idle flush will prevent lost prints, and a no-newline output API will improve streaming UX.