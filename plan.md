# Console I/O Simplification Plan

## Problem Statement

Current console I/O system is overly complex and has fundamental issues:
- Uses ncurses with 80/20 split screen layout
- Implements custom scrollback (user wants terminal's native scrollback)
- Implements custom copy/paste handling (user wants terminal's native selection)
- Multiple layers: OutputBuffer → OutputManager → TUIManager
- **Core issue**: Need background threads to write output while user is typing, without corrupting the input line

## Desired User Experience

The terminal should feel like a normal scrollable terminal window, but with a "floating" bottom line that's always one of:
- **`"> "` prompt** - waiting for user input, OR
- **Spinner** - showing orchestrator is thinking

### Specific Behaviors

1. **While waiting for input (`"> "` visible)**:
   - User can type normally
   - Background threads can output at any time
   - When background output arrives:
     - Input line clears
     - Output prints above (becomes part of permanent history)
     - Input line redraws at new bottom with what user had typed
   - User presses Enter:
     - Command is added to permanent history above
     - Spinner replaces prompt (if orchestrator starts processing)
     - OR new prompt appears (if ready for next input)

2. **While orchestrator is processing (spinner visible)**:
   - Spinner animates at bottom of screen
   - Background threads can still output
   - When background output arrives:
     - Spinner clears
     - Output prints above
     - Spinner redraws at new bottom
   - User presses Ctrl-C:
     - Orchestrator aborts
     - Spinner is replaced with `"> "` prompt
     - Any buffered keystrokes are flushed/ignored

3. **Terminal features work normally**:
   - Native scrollback works (scroll up to see history)
   - Native copy/paste works (select text with mouse/keyboard)
   - All output is permanent and scrollable

### Visual Flow

```
Terminal at rest (waiting for input):
┌────────────────────────────────┐
│ previous output line 1         │
│ previous output line 2         │
│ ...                            │
│ > what I'm typing|             │ ← floating input line
└────────────────────────────────┘

Background output arrives:
┌────────────────────────────────┐
│ previous output line 1         │
│ previous output line 2         │
│ ...                            │
│ NEW: background output!        │ ← new output added to history
│ > what I'm typing|             │ ← input line redrawn at bottom
└────────────────────────────────┘

User hits Enter, orchestrator starts:
┌────────────────────────────────┐
│ previous output line 2         │
│ ...                            │
│ NEW: background output!        │
│ > what I was typing            │ ← command now in history
│ ⠋ Thinking...                  │ ← spinner replaces prompt
└────────────────────────────────┘

More background output during processing:
┌────────────────────────────────┐
│ ...                            │
│ > what I was typing            │
│ MORE: background output!       │ ← more output added
│ ⠙ Thinking...                  │ ← spinner redrawn, animated
└────────────────────────────────┘
```

## Solution: Non-blocking I/O with Floating Bottom Line

Use `IO.select` to monitor both user input and background output, redrawing the bottom line (prompt or spinner) when interrupted.

### Key Principles
1. ✅ Use terminal's native scrollback and copy/paste
2. ✅ No ncurses or similar libraries
3. ✅ Background threads can interrupt and display output immediately
4. ✅ Keep it simple - minimal layers
5. ✅ Bottom line (prompt or spinner) always visible and preserved
6. ✅ All output becomes permanent scrollable history
7. ✅ Emulate Readline features (don't use actual Readline gem)

### Why Emulate Readline Instead of Using It?

**Using actual Readline gem**:
- ❌ Readline.readline() is blocking and takes over terminal control
- ❌ Cannot interrupt it cleanly when background output arrives
- ❌ Would fight with our select loop and redrawing logic

**Emulating Readline**:
- ✅ Full control over when to redraw for background output
- ✅ Compatible with our select loop architecture
- ✅ Simpler - implement only features we need
- ✅ Works seamlessly with both input mode and spinner mode

## Architecture

```
┌─────────────────────────────────────────┐
│  Background Threads (anywhere in code)  │
└──────────────┬──────────────────────────┘
               │ writes to
               ▼
        ┌──────────────┐
        │ Output Queue │ (thread-safe)
        └──────┬───────┘
               │
               ▼
    ┌──────────────────────┐
    │   Main Select Loop   │
    │  (monitors stdin +   │
    │   output queue)      │
    └──────────────────────┘
          │         │
    stdin │         │ queue has data
          ▼         ▼
    ┌─────────┐  ┌──────────┐
    │  Input  │  │  Output  │
    │ Handler │  │ Handler  │
    └─────────┘  └──────────┘
         │            │
         ▼            ▼
    Update line   Clear bottom line (prompt or spinner)
    buffer &      → Write output (permanent history)
    display       → Redraw bottom line
```

## ANSI Color Support

**Output (background threads, permanent history)**:
- ✅ Full ANSI color code support
- Colors pass through as-is, terminal renders them
- Example: `console.puts("\e[32mSuccess!\e[0m")` displays green text

**Spinner**:
- ✅ Can include ANSI codes in spinner message if desired
- Example: `console.show_spinner("\e[33mThinking...\e[0m")` for yellow text

**Input line (prompt + user typing)**:
- Plain white/default terminal color
- NO ANSI codes in prompt or user input
- Cursor positioning: simple arithmetic (no display-width calculations needed)
- Prompt: `"> "` (plain text, no colors)

This keeps implementation simple - no ANSI stripping or width calculations for input line.

## Implementation Phases

Each phase is independently shippable. Stop when "good enough" is reached.

### Phase 1: Core System (Minimal Input)
**Goal**: Prove the core concept works

**Features**:
- Floating prompt/spinner at bottom
- Background output interrupts and redraws cleanly
- Basic input: type printable characters, Enter to submit
- Backspace works (delete char before cursor)
- Ctrl-C raises Interrupt
- Ctrl-D returns nil if buffer empty
- Spinner mode with animation
- Terminal's native scrollback and copy/paste work

**No advanced editing yet** - can't move cursor, no history, single line only

**Deliverable**: Usable system that validates the approach

---

### Phase 2: Basic Readline Editing Emulation
**Goal**: Comfortable single-line editing experience

**Add these features**:
- Arrow keys (left/right) move cursor within line
- Home/End keys jump to start/end of line
- Ctrl-A/Ctrl-E (emacs-style home/end)
- Delete key removes character at cursor
- Ctrl-K kills (cuts) from cursor to end of line
- Ctrl-U kills from cursor to start of line
- Ctrl-W kills word backward
- Ctrl-Y yanks (pastes) killed text
- Ctrl-L clears screen
- Insert characters at cursor position (not just end)

**Still single-line, no history yet**

**Deliverable**: Full-featured single-line editing like Readline

---

### Phase 3: Command History Emulation
**Goal**: Reuse previous commands

**Add these features**:
- Store all submitted commands in array
- Up/Down arrows cycle through history
- Walking through history preserves current partially-typed input
- History persists across session (save to database)
- Load history on startup

**Deliverable**: Can recall and reuse previous commands

---

### Phase 4: History Search Emulation
**Goal**: Quick access to any previous command

**Add these features**:
- Ctrl-R for reverse incremental search
- Type to filter matching commands from history
- Shows matching command as you type
- Enter selects current match
- Ctrl-R again cycles to next match
- Ctrl-G or Ctrl-C cancels search

**Deliverable**: Fast command recall like Readline's Ctrl-R

---

### Phase 5: External Editor for Multiline Input (Recommended)
**Goal**: Allow composing complex multiline prompts without implementing complex inline editing

**Key insight**: Instead of building multiline editing into the terminal (complex cursor navigation, line joining, etc.), leverage the user's preferred text editor via **Ctrl-G**.

**How it works**:
1. User presses **Ctrl-G** at the `> ` prompt
2. All background tasks pause (man indexer, database summarizer, etc.)
3. Terminal exits raw mode, returns to normal "cooked" mode
4. Temp file created (pre-populated with current input buffer if any)
5. User's `$VISUAL` or `$EDITOR` launches (Vi, Vim, Nano, Emacs, etc.)
6. User edits with full power of their chosen editor
7. User saves and exits (`:wq` in Vi, Ctrl-X in Nano, etc.)
8. Background tasks resume
9. Terminal re-enters raw mode
10. Content from temp file is submitted (shows in history, starts orchestrator)
11. If user exits without saving, return to prompt (no submission)

**Visual flow**:
```
Before Ctrl-G:
│ Tool: Reading file...     │
│ Tool: Processing...       │
│ > what I started ty|      │  ← User presses Ctrl-G

[Input line clears, Vi opens in alternate screen]
[User edits multiline prompt with full Vi power]
[User exits Vi with :wq]

[Back to main screen where we left off]
│ Tool: Reading file...     │
│ Tool: Processing...       │
│ > Please analyze this:    │  ← Submitted content
│ def foo                   │
│   bar                     │
│ end                       │
│ ⠋ Thinking...             │  ← Orchestrator starts
```

**Benefits over inline multiline**:
- ✅ **Simpler implementation** - No complex multiline cursor logic
- ✅ **More powerful** - Full Vi/Emacs/etc editing capabilities
- ✅ **Familiar pattern** - Same as `git commit`, `crontab -e`, bash `fc`
- ✅ **Configurable** - Respects user's `$EDITOR` preference
- ✅ **Clean UX** - Terminal scrollback preserved, conversation continues seamlessly

**Environment variable handling**:
```ruby
editor = ENV['VISUAL'] || ENV['EDITOR'] || 'vi'
```
Checks `$VISUAL` first (traditional for visual editors), then `$EDITOR`, falls back to `vi` (guaranteed to exist on Unix).

**Keybinding**: Ctrl-G (mnemonic: "Go to editor"). Could also support Ctrl-X Ctrl-E (bash `edit-and-execute-command` binding).

**Deliverable**: External editor integration for multiline composition

**IMPORTANT: Requires Pausable Background Tasks** (see new section below)

---

## Pausable Background Tasks

**Why needed**: Nu-agent runs continuous background workers (man indexer, database summarizer, future semantic indexers, etc.) that are independent of the orchestrator's request/response cycle. When the user opens an external editor (Ctrl-G), these tasks must pause cleanly to prevent:
1. Output queueing during editing (could become large)
2. Resource contention while user is composing
3. Unexpected behavior when resuming

**Architecture**: All background workers inherit from a `PausableTask` base class:

```ruby
# lib/nu/agent/pausable_task.rb
class PausableTask
  def initialize(name)
    @name = name
    @paused = false
    @pause_mutex = Mutex.new
    @pause_cv = ConditionVariable.new
    @running = false
  end

  def start
    @running = true
    @thread = Thread.new { run_loop }
  end

  def pause
    @pause_mutex.synchronize do
      @paused = true
    end
  end

  def resume
    @pause_mutex.synchronize do
      @paused = false
      @pause_cv.broadcast
    end
  end

  def wait_until_paused(timeout = 5)
    # Wait for thread to reach pause checkpoint
    start_time = Time.now
    loop do
      return true if truly_paused?
      return false if Time.now - start_time > timeout
      sleep 0.01
    end
  end

  def stop
    @running = false
    resume  # Wake up if paused
    @thread&.join
  end

  private

  def truly_paused?
    @paused && @thread.status == 'sleep'
  end

  # Worker calls this at safe checkpoints
  def check_pause
    @pause_mutex.synchronize do
      while @paused && @running
        @pause_cv.wait(@pause_mutex)
      end
    end
  end

  # Override in subclass
  def run_loop
    raise NotImplementedError
  end
end
```

**Example worker implementation**:
```ruby
class ManIndexer < PausableTask
  def initialize(db)
    super("ManIndexer")
    @db = db
  end

  private

  def run_loop
    loop do
      break unless @running

      check_pause  # Yield here if paused

      # Do a chunk of work
      index_next_batch

      sleep 1  # Rate limit
    end
  end
end
```

**Application integration**:
```ruby
class Application
  def initialize
    @background_tasks = []
    @background_tasks << ManIndexer.new(@db).tap(&:start)
    @background_tasks << DatabaseSummarizer.new(@db).tap(&:start)
  end

  def pause_all_background_tasks
    @background_tasks.each(&:pause)
    @background_tasks.each do |task|
      warn "Warning: #{task.name} didn't pause" unless task.wait_until_paused
    end
  end

  def resume_all_background_tasks
    @background_tasks.each(&:resume)
  end

  def shutdown
    @background_tasks.each(&:stop)
  end
end
```

**Key design principles**:
1. **Cooperative pausing** - Tasks must call `check_pause` at safe points (between operations, not mid-transaction)
2. **Timeout safety** - If task doesn't pause in 5 seconds, warn and continue (don't hang editor launch)
3. **Graceful** - Tasks pause/resume at clean boundaries
4. **Universal** - All future background workers use same pattern

---

## Core Components

### 1. ConsoleIO Class (new)
Replaces TUIManager, OutputManager, OutputBuffer with a single unified class.

**Location**: `lib/nu/agent/console_io.rb`

**Responsibilities**:
- Set up/tear down raw terminal mode
- Run main select loop (input mode)
- Handle user input character by character
- Handle background output from queue
- Redraw bottom line when interrupted
- Manage kill ring (for Ctrl-K/Ctrl-U/Ctrl-W/Ctrl-Y)
- Manage command history
- Spinner animation and Ctrl-C monitoring (spinner mode)

**Public API**:
```ruby
console = ConsoleIO.new

# Thread-safe output from background threads
console.puts(text)                    # Adds text to queue
console.puts("\e[32mSuccess!\e[0m")   # ANSI colors supported

# Blocking read with interruption support
line = console.readline("> ")         # Returns user input or nil (Ctrl-D)

# Spinner mode
console.show_spinner("Thinking...")   # Show spinner, return immediately
# ... orchestrator processes in background ...
# ... background threads can call console.puts() ...
console.hide_spinner                  # Hide spinner, prepare for next prompt

# Cleanup
console.close                         # Restore terminal state
```

**Usage pattern in application**:
```ruby
console = ConsoleIO.new

at_exit { console.close }  # Always restore terminal

loop do
  line = console.readline("> ")
  break if line.nil?  # Ctrl-D

  console.show_spinner("Thinking...")

  # Orchestrator processes in background thread
  # Background threads call console.puts() during processing

  # When done:
  console.hide_spinner

  # Next prompt appears
end
```

**Modes**:
- **Input mode**: Showing `"> "` prompt, accepting user input via select loop
- **Spinner mode**: Showing animated spinner via background thread

**State tracking**:
```ruby
# Input mode state
@input_buffer = ""           # Current user input
@cursor_pos = 0              # Cursor position (0 to buffer.length)
@kill_ring = ""              # Killed text (for Ctrl-K/U/W/Y)
@history = []                # Array of previous commands
@history_pos = nil           # Current position in history (nil = new input)
@saved_input = ""            # Saved current input when browsing history

# Spinner mode state
@spinner_message = ""        # e.g., "Thinking..."
@spinner_frame = 0           # Current animation frame index
@spinner_frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
@spinner_running = false     # Is spinner thread active?
@spinner_thread = nil        # Background thread reference

# Shared state
@mode = :input               # :input or :spinner
@output_queue = Queue.new    # Thread-safe queue
@output_pipe_read = nil      # Pipe for select monitoring
@output_pipe_write = nil     # Pipe for signaling
@mutex = Mutex.new           # For stdout writes
@application = nil           # Reference to Application for pausing background tasks (Phase 5)
```

### 2. Terminal Raw Mode

Use Ruby's `io/console` stdlib:

```ruby
require 'io/console'

def setup_terminal
  @stdin = $stdin
  @stdout = $stdout

  # Save original state
  @original_stty = `stty -g`.chomp

  # Enter raw mode (no echo, no line buffering)
  @stdin.raw!

  # Register cleanup
  at_exit { restore_terminal }
end

def restore_terminal
  return unless @original_stty

  # Restore original state
  system("stty #{@original_stty}")

  # Show cursor
  @stdout.write("\e[?25h")
  @stdout.flush
end
```

**Important**: Always restore terminal state, even on crashes or Ctrl-C.

### 3. Output Queue with Signaling

Background threads need to wake up the select loop:

```ruby
def initialize
  @output_queue = Queue.new
  @output_pipe_read, @output_pipe_write = IO.pipe
  @mutex = Mutex.new
end

def puts(text)
  # Thread-safe: add to queue and signal
  @output_queue.push(text)
  @output_pipe_write.write("x")  # Signal select loop
rescue
  # Ignore if pipe closed
end

def drain_output_queue
  lines = []

  # Drain pipe signals
  begin
    @output_pipe_read.read_nonblock(1024)
  rescue IO::WaitReadable, EOFError
    # Empty
  end

  # Drain queue
  loop do
    lines << @output_queue.pop(true)
  rescue ThreadError
    break  # Queue empty
  end

  lines
end
```

### 4. Input Parsing

Parse character-by-character, handle escape sequences:

```ruby
def parse_input(raw)
  chars = raw.chars

  chars.each do |char|
    case char
    when "\r", "\n"
      # Enter pressed
      return :submit

    when "\x03"  # Ctrl-C
      raise Interrupt

    when "\x04"  # Ctrl-D
      return :eof if @input_buffer.empty?

    when "\x7F", "\b"  # Backspace
      delete_backward

    when "\x01"  # Ctrl-A
      cursor_to_start

    when "\x05"  # Ctrl-E
      cursor_to_end

    when "\x0B"  # Ctrl-K
      kill_to_end

    when "\x15"  # Ctrl-U
      kill_to_start

    when "\x17"  # Ctrl-W
      kill_word_backward

    when "\x19"  # Ctrl-Y
      yank

    when "\x0C"  # Ctrl-L
      clear_screen

    when "\x07"  # Ctrl-G
      return :open_editor

    when "\e"  # Escape - start of sequence
      # Read rest of escape sequence
      # Arrow keys: \e[A (up), \e[B (down), \e[C (right), \e[D (left)
      # Delete: \e[3~
      # Home: \e[H or \e[1~
      # End: \e[F or \e[4~
      handle_escape_sequence(chars)

    else
      # Printable character
      if char.ord >= 32 && char.ord <= 126
        insert_char(char)
      end
    end
  end

  nil  # Continue reading
end
```

### 5. Line Redrawing

Simple redraw for single line:

```ruby
def redraw_input_line(prompt)
  @mutex.synchronize do
    # Clear line
    @stdout.write("\e[2K\r")

    # Redraw prompt and buffer
    @stdout.write(prompt)
    @stdout.write(@input_buffer)

    # Position cursor
    # Formula: prompt.length + @cursor_pos + 1 (1-indexed)
    col = prompt.length + @cursor_pos + 1
    @stdout.write("\e[#{col}G")

    @stdout.flush
  end
end
```

### 6. History Management

```ruby
def add_to_history(line)
  # Don't add empty lines or duplicates of last entry
  return if line.strip.empty?
  return if !@history.empty? && @history.last == line

  @history << line

  # TODO Phase 3: Save to database
end

def history_prev
  # Move back in history
  if @history_pos.nil?
    # Starting from current input
    @saved_input = @input_buffer
    @history_pos = @history.length - 1
  else
    @history_pos -= 1 if @history_pos > 0
  end

  @input_buffer = @history[@history_pos] || ""
  @cursor_pos = @input_buffer.length
end

def history_next
  # Move forward in history
  return unless @history_pos

  @history_pos += 1

  if @history_pos >= @history.length
    # Reached end - restore saved input
    @input_buffer = @saved_input
    @history_pos = nil
  else
    @input_buffer = @history[@history_pos]
  end

  @cursor_pos = @input_buffer.length
end
```

### 7. Spinner Implementation

Background thread with animation and Ctrl-C monitoring:

```ruby
def show_spinner(message)
  @mode = :spinner
  @spinner_message = message
  @spinner_frame = 0
  @spinner_running = true

  # Flush stdin before starting spinner
  flush_stdin

  @spinner_thread = Thread.new do
    begin
      loop do
        break unless @spinner_running

        # Check for output or Ctrl-C with 100ms timeout
        readable, _, _ = IO.select([@stdin, @output_pipe_read], nil, nil, 0.1)

        if readable
          readable.each do |io|
            if io == @output_pipe_read
              # Background output arrived
              handle_output_for_spinner_mode
            elsif io == @stdin
              # Check for Ctrl-C
              char = @stdin.read_nonblock(1) rescue nil
              if char == "\x03"
                @spinner_running = false
                flush_stdin
                raise Interrupt
              end
              # Ignore other keystrokes
            end
          end
        else
          # Timeout - animate spinner
          animate_spinner
        end
      end
    rescue Interrupt
      hide_spinner
      raise
    end
  end
end

def hide_spinner
  @spinner_running = false
  @spinner_thread&.join

  @mutex.synchronize do
    @stdout.write("\e[2K\r")  # Clear spinner line
    @stdout.flush
  end

  # Flush stdin when returning to input mode
  flush_stdin
end

def animate_spinner
  @spinner_frame = (@spinner_frame + 1) % @spinner_frames.length
  redraw_spinner
end

def redraw_spinner
  @mutex.synchronize do
    @stdout.write("\e[2K\r")
    frame = @spinner_frames[@spinner_frame]
    @stdout.write("#{frame} #{@spinner_message}")
    @stdout.flush
  end
end

def flush_stdin
  # Drain all buffered input
  loop do
    readable, _, _ = IO.select([@stdin], nil, nil, 0)
    break unless readable
    @stdin.read_nonblock(1024) rescue break
  end
end
```

### 8. External Editor Integration

Open user's preferred editor for multiline input composition:

```ruby
def open_editor_for_input
  # Pause all background tasks
  @application.pause_all_background_tasks

  # Clear current input line
  @mutex.synchronize do
    @stdout.write("\e[2K\r")
    @stdout.flush
  end

  # Exit raw mode
  restore_terminal

  begin
    # Create temp file
    require 'tempfile'
    file = Tempfile.new(['nu-agent-input', '.txt'])

    # Pre-populate with current buffer if user was typing
    file.write(@input_buffer) unless @input_buffer.empty?
    file.flush
    file.close

    # Launch editor (respects $VISUAL, $EDITOR, falls back to vi)
    editor = ENV['VISUAL'] || ENV['EDITOR'] || 'vi'
    system("#{editor} #{file.path}")
    # ^ This blocks until editor exits
    # ^ Editor uses alternate screen buffer (Vi/Vim)
    # ^ When editor exits, we return to main screen

    # Read what user wrote
    content = File.read(file.path).strip

    # Return nil if empty (user didn't save or saved empty file)
    return nil if content.empty?

    content

  ensure
    file.unlink if file

    # Resume background tasks BEFORE restoring terminal
    # (so any immediate output gets queued properly)
    @application.resume_all_background_tasks

    # Re-enter raw mode
    setup_terminal

    # Drain any output that queued during brief resume window
    lines = drain_output_queue
    @mutex.synchronize do
      lines.each { |line| @stdout.puts(line) }
      @stdout.flush
    end

    # DON'T clear screen - terminal scrollback preserved
    # Conversation continues where it left off
  end
end
```

**How `system()` works**:
1. Ruby forks a child process
2. Child execs the editor with the temp file path
3. Child inherits parent's stdin/stdout/stderr (the terminal)
4. Parent Ruby process blocks at `system()` call
5. Editor takes over the screen (usually using alternate screen buffer)
6. User edits, saves, exits
7. Editor exits, `system()` returns
8. Execution continues

**Why `system()` not `popen()`**:
- `system()` gives child direct terminal access (TTY)
- `popen()` would create pipes, confusing editors that need a TTY
- `system()` is synchronous - exactly what we want

**Terminal scrollback preservation**:
- Most modern Vi/Vim use alternate screen buffer (`\e[?1049h`)
- When editor exits, switches back to main buffer (`\e[?1049l`)
- Terminal scrollback untouched - all conversation history still accessible
- We don't clear screen after returning - conversation continues seamlessly

```

## Technical Details

### Select Loop Pattern (Input Mode)

```ruby
def readline(prompt)
  @mode = :input
  @input_buffer = ""
  @cursor_pos = 0
  @history_pos = nil
  @saved_input = ""

  redraw_input_line(prompt)

  loop do
    # Monitor stdin and output pipe
    readable, _, _ = IO.select([@stdin, @output_pipe_read], nil, nil)

    readable.each do |io|
      if io == @output_pipe_read
        # Background output arrived
        handle_output_for_input_mode(prompt)

      elsif io == @stdin
        # User input arrived
        raw = @stdin.read_nonblock(1024) rescue ""

        result = parse_input(raw)

        case result
        when :submit
          line = @input_buffer.dup

          # Add to permanent history
          @mutex.synchronize do
            @stdout.write("\e[2K\r")
            @stdout.write(prompt)
            @stdout.puts(line)
          end

          add_to_history(line)
          return line

        when :eof
          # Ctrl-D on empty buffer
          @mutex.synchronize do
            @stdout.write("\e[2K\r")
            @stdout.flush
          end
          return nil

        when :open_editor
          # Ctrl-G - open external editor
          content = open_editor_for_input
          if content
            # User saved content - submit it
            @mutex.synchronize do
              @stdout.write(prompt)
              @stdout.puts(content)
            end
            add_to_history(content)
            return content
          else
            # User cancelled or saved empty - return to prompt
            redraw_input_line(prompt)
          end
        end

        # Redraw after processing input
        redraw_input_line(prompt)
      end
    end
  end
end
```

### Output Handler Pattern

```ruby
def handle_output_for_input_mode(prompt)
  lines = drain_output_queue
  return if lines.empty?

  @mutex.synchronize do
    # Clear current input line
    @stdout.write("\e[2K\r")

    # Write all output (with ANSI colors preserved)
    lines.each { |line| @stdout.puts(line) }

    # Redraw input line at new bottom
    @stdout.write(prompt)
    @stdout.write(@input_buffer)

    col = prompt.length + @cursor_pos + 1
    @stdout.write("\e[#{col}G")

    @stdout.flush
  end
end

def handle_output_for_spinner_mode
  lines = drain_output_queue
  return if lines.empty?

  @mutex.synchronize do
    # Clear spinner line
    @stdout.write("\e[2K\r")

    # Write all output
    lines.each { |line| @stdout.puts(line) }

    # Redraw spinner at new bottom
    frame = @spinner_frames[@spinner_frame]
    @stdout.write("#{frame} #{@spinner_message}")

    @stdout.flush
  end
end
```

### Escape Sequence Handling

```ruby
def handle_escape_sequence(chars)
  # Peek at next characters
  # Common sequences:
  # \e[A - up arrow
  # \e[B - down arrow
  # \e[C - right arrow
  # \e[D - left arrow
  # \e[3~ - delete
  # \e[H or \e[1~ - home
  # \e[F or \e[4~ - end

  return unless chars.first == '['
  chars.shift  # consume '['

  case chars.first
  when 'A'  # Up arrow
    chars.shift
    history_prev

  when 'B'  # Down arrow
    chars.shift
    history_next

  when 'C'  # Right arrow
    chars.shift
    cursor_forward

  when 'D'  # Left arrow
    chars.shift
    cursor_backward

  when 'H'  # Home
    chars.shift
    cursor_to_start

  when 'F'  # End
    chars.shift
    cursor_to_end

  when '1'
    chars.shift
    if chars.first == '~'
      chars.shift
      cursor_to_start  # Home variant
    end

  when '3'
    chars.shift
    if chars.first == '~'
      chars.shift
      delete_forward  # Delete key
    end

  when '4'
    chars.shift
    if chars.first == '~'
      chars.shift
      cursor_to_end  # End variant
    end
  end
end
```

## Files to Modify

### New Files
- `lib/nu/agent/console_io.rb` - New unified console handler
- `lib/nu/agent/pausable_task.rb` - Base class for pausable background workers

### Modified Files
- `lib/nu/agent/application.rb` - Replace TUIManager with ConsoleIO, add background task management
- `lib/nu/agent/formatter.rb` - Update output calls to use `console.puts()`
- `lib/nu/agent/options.rb` - Remove --tui flag (new system always on)
- `lib/nu/agent/tools/man_indexer.rb` - Inherit from PausableTask
- `lib/nu/agent/tools/agent_summarizer.rb` - Inherit from PausableTask (or similar)

### Removed Files (after Phase 1 complete)
- `lib/nu/agent/tui_manager.rb` - Delete
- `lib/nu/agent/output_manager.rb` - Delete
- `lib/nu/agent/output_buffer.rb` - Delete

### Documentation Updates
- `README.md` - Update to describe new console behavior
- `TUI_USAGE.md` - Remove (no longer relevant)
- `ncurses.md` - Remove (no longer using ncurses)

## Edge Cases to Handle

1. **Terminal resize (SIGWINCH)**: Just let it scroll naturally, no special handling needed
2. **Very long input lines**: Let terminal wrap naturally (can improve in later phase)
3. **Multi-byte UTF-8**: Use `String#chars` instead of bytes for cursor positioning
4. **Output during redraw**: Queued and handled in next select iteration
5. **Rapid output bursts**: Drain all queued items in single redraw operation
6. **Ctrl-C during readline**: Raise Interrupt, restore terminal in ensure block
7. **Ctrl-C during spinner**: Stop spinner, raise Interrupt, flush stdin, restore terminal
8. **Ungraceful exit**: Use `at_exit` hook to always restore terminal state
9. **Keystrokes buffered during spinner**: Flush stdin when returning to input mode
10. **Concurrent output from multiple threads**: Queue is thread-safe, drained atomically
11. **Empty input on Ctrl-D**: Return nil to signal EOF
12. **ANSI codes in output**: Pass through as-is, terminal renders colors correctly
13. **Input longer than terminal width**: Let it wrap (buffer still contains full text)
14. **Ctrl-G during editor open**: Already in editor - no action (editor handles its own keys)
15. **Editor exits without saving**: Return to prompt, no submission (content nil check)
16. **Background task won't pause**: Timeout after 5 seconds, warn, continue anyway
17. **$EDITOR not set**: Fall back to 'vi' (guaranteed on Unix systems)
18. **$EDITOR is GUI app (e.g., "code --wait")**: Works if app supports blocking mode
19. **Background output during editor**: Queued, drained when editor exits, shown above prompt
20. **Terminal scrollback while in editor**: Preserved - editor uses alternate screen

## Testing Strategy

### Phase 1 Testing
1. Start agent, verify prompt appears
2. Type characters, press Enter, verify input captured
3. Background thread outputs during typing - verify input preserved and redrawn
4. Submit command, verify spinner appears
5. Background output during spinner - verify spinner redrawn
6. Ctrl-C during spinner - verify abort and return to prompt
7. Verify terminal scrollback works (scroll up to see history)
8. Verify copy/paste works (select text with mouse)
9. Test ANSI colors in output - verify they render correctly
10. Long session - verify no memory leaks

### Phase 2 Testing
11. Arrow keys move cursor correctly
12. Home/End jump to start/end
13. Ctrl-K/U/W kill text correctly
14. Ctrl-Y yanks killed text
15. Insert characters at cursor position
16. Delete key removes character at cursor
17. Background output during editing - verify cursor position preserved

### Phase 3 Testing
18. Submit multiple commands, verify they're stored
19. Up arrow recalls previous commands
20. Down arrow moves forward in history
21. Walk to history, then type new command - verify it works
22. History persists across restarts (database)

### Phase 4 Testing
23. Ctrl-R activates search
24. Type search term - verify matching commands shown
25. Ctrl-R again cycles through matches
26. Enter selects match
27. Ctrl-G cancels search

### Phase 5 Testing (External Editor)
28. Ctrl-G opens $EDITOR with empty buffer
29. Ctrl-G with partially typed input - verify pre-populated in editor
30. Edit and save - verify content submitted and shown in history
31. Edit and exit without saving (:q!) - verify return to prompt, no submission
32. Background tasks pause during editing - verify no output while in editor
33. Background output queued during editing - verify shown after editor exits
34. Terminal scrollback preserved after editor - verify can scroll up to see history
35. Try different editors (vi, vim, nano, emacs) - verify all work
36. $EDITOR not set - verify falls back to vi
37. Multiline content from editor - verify submits correctly
38. Very large content from editor - verify handles without issues

## Success Criteria

- ✅ Background threads can output while user is typing (input mode)
- ✅ Background threads can output while orchestrator is processing (spinner mode)
- ✅ Input line is preserved and redrawn after output interruption
- ✅ Spinner is preserved and redrawn after output interruption
- ✅ Spinner animates smoothly (~10 FPS)
- ✅ Terminal's native scrollback works
- ✅ Terminal's native copy/paste works
- ✅ ANSI colors in output work correctly
- ✅ Simpler codebase (one file vs three)
- ✅ No ncurses dependency
- ✅ Feels responsive and natural
- ✅ Ctrl-C during spinner returns to prompt cleanly
- ✅ Stdin is flushed when returning to input mode (no phantom keystrokes)
- ✅ Readline-style editing works (Phase 2+)
- ✅ Command history works (Phase 3+)
- ✅ History search works (Phase 4+)
- ✅ External editor integration works (Phase 5)
- ✅ Background tasks pause/resume cleanly for editor
- ✅ Respects user's $EDITOR preference

## Rollback Plan

Keep old code in git history. If new system has issues:
1. Revert commits to return to TUIManager
2. Re-enable --tui flag temporarily
3. Fix issues incrementally
4. Try again

Each phase is independently testable and can be reverted if needed.

## Potential Challenges

### 1. Raw Terminal Mode Complexity
**Challenge**: Managing terminal state across crashes, Ctrl-C, and errors.

**Solution**:
- Use `at_exit` hook to always restore terminal
- Wrap main loop in begin/ensure block
- Test cleanup with various failure modes

### 2. Escape Sequence Parsing
**Challenge**: Arrow keys send multi-byte escape sequences (e.g., `\e[A` for up).

**Solution**:
- Read sequences character by character
- Build state machine or peek ahead in buffer
- Handle common sequences, ignore unknown ones

### 3. Spinner Thread Synchronization
**Challenge**: Spinner thread accessing shared stdout and queue.

**Solution**:
- Use mutex for all stdout writes
- Queue is already thread-safe
- Use select with timeout for animation timing

### 4. Stdin Flushing
**Challenge**: Clearing buffered input when returning to prompt.

**Solution**:
- Use `IO.select` with 0 timeout
- Drain with read_nonblock until empty
- Call before showing prompt after spinner

### 5. Line Wrapping
**Challenge**: Very long input lines exceed terminal width.

**Solution**:
- Initially, let terminal wrap naturally
- Buffer contains full text regardless of display
- Can add smart wrapping in later phase

### 6. UTF-8 Characters
**Challenge**: Multi-byte characters affect cursor positioning.

**Solution**:
- Use `String#chars` for iteration (handles UTF-8)
- Count characters, not bytes
- Terminal handles display width

## Alternative Approaches Considered

### Alternative 1: Use Readline gem
**Pros**: Built-in editing, history, completion.

**Cons**:
- Readline.readline() is blocking
- Cannot interrupt for background output
- Would fight with our select loop

**Decision**: Emulate instead for full control.

### Alternative 2: Keep ncurses
**Pros**: Proven library, handles complexity.

**Cons**:
- Doesn't provide native scrollback/copy-paste
- Custom scrollback is complex and incomplete
- Defeats main goal of simplification

**Decision**: Not chosen - defeats purpose.

### Alternative 3: Just print output, accept corruption
**Pros**: Dead simple, no redrawing needed.

**Cons**:
- UX is poor - input line gets corrupted
- Confusing for users

**Decision**: Not chosen - UX too important.

### Alternative 4: Buffer output until Enter
**Pros**: No interruption complexity.

**Cons**:
- User doesn't see background output while typing
- Defeats real-time monitoring goal

**Decision**: Not chosen - want real-time output.

## Notes

- This approach gives us "best of both worlds": normal terminal behavior (scrollback, copy/paste) with clean UX (floating input/spinner)
- Key insight: Don't need ncurses - ANSI escapes for clearing/redrawing bottom line are sufficient
- Thread safety is critical - all stdout writes must be mutex-protected
- Select loop is the heart of the system - multiplexes user input and background output
- Each phase builds on previous - can stop when "good enough"
- Emulating Readline is simpler than fighting with actual Readline gem
- Spinner mode uses background thread, input mode uses main thread with select
- **External editor for multiline** (Phase 5) is a better design than inline multiline:
  - Simpler implementation - no complex cursor navigation across lines
  - More powerful - full Vi/Emacs capabilities instead of limited emulation
  - Familiar pattern - users know it from git, crontab, etc.
  - Requires pausable background tasks to prevent output buffering issues
  - Uses `system()` for synchronous blocking (not `popen()` which would confuse editors)
  - Terminal scrollback preserved via editor's alternate screen buffer
  - Respects user's `$EDITOR` preference, falls back to `vi`

## Implementation Order

1. **Phase 1**: Get basic system working, validate approach
2. **Test thoroughly**: Ensure core concept is solid
3. **Phase 2**: Add editing comfort features
4. **Evaluate**: Is this good enough? Or continue to Phase 3?
5. **Phase 3**: Add history if needed
6. **Evaluate**: Is this good enough? Or continue to Phase 4?
7. **Phase 4**: Add history search if needed
8. **Evaluate**: Is this good enough? Or continue to Phase 5?
9. **Phase 5**: Implement PausableTask base class and external editor integration
   - Convert existing background workers (ManIndexer, etc.) to PausableTask
   - Add Ctrl-G handler for external editor
   - Much simpler than inline multiline editing

Stop at any phase if it meets requirements. Don't over-engineer.

**Note**: Phase 5 is now SIMPLER than originally planned - external editor is easier to implement and more powerful than inline multiline editing.

## Implementation Strategy (Updated 2025-10-26)

### Code Preservation
- **Tag**: `tui-experiment` - Preserves ncurses TUI implementation before Console I/O simplification
- Existing TUI code will be removed as new ConsoleIO is implemented
- No parallel modes - ConsoleIO will be the only console system
- No flags needed to distinguish modes (--tui flag will be removed)

### Development Approach
1. **Test-Driven Development (TDD)**:
   - Write RSpec tests FIRST before implementing features
   - Each phase should have comprehensive test coverage
   - Tests validate behavior before code is written

2. **Code Quality**:
   - Run Rubocop on all new and modified files
   - Correct all errors and warnings before committing
   - Existing files exempt from Rubocop requirements

3. **Incremental Removal**:
   - Remove old TUI code as ConsoleIO replaces functionality
   - Files to remove after Phase 1 complete:
     - `lib/nu/agent/tui_manager.rb`
     - `lib/nu/agent/output_manager.rb`
     - `lib/nu/agent/output_buffer.rb`

4. **Testing Strategy**:
   - RSpec test suite for ConsoleIO class
   - Test individual methods (redraw, input parsing, etc.)
   - Mock IO for deterministic testing
   - Integration tests with real terminal (optional/manual)

### Migration Path
1. Write RSpec tests for ConsoleIO Phase 1 features
2. Implement ConsoleIO to pass tests
3. Update Application to use ConsoleIO instead of TUIManager/OutputManager
4. Update Formatter to use ConsoleIO output methods
5. Remove old TUI files
6. Update Options to remove --tui flag
7. Repeat for subsequent phases

## Phase 1 Implementation Notes (2025-10-26)

### Code Organization
- **Method extraction for Rubocop compliance**: The `readline` method was refactored into smaller helper methods:
  - `handle_readline_select` - Main select loop iteration
  - `handle_stdin_input` - Process user input
  - `submit_input` - Handle Enter key submission
  - `handle_eof` - Handle Ctrl-D EOF
  - This pattern improves both testability and maintainability

### Testing Strategy
- **Mock setup for IO objects**: ConsoleIO requires careful mock configuration in tests
  - Must use `instance_double(IO)` for stdin, stdout, and pipe objects
  - Must use `allow(pipe_write).to receive(:write)` to permit signaling in background threads
  - Queue operations need rescue blocks for ThreadError (queue empty)
  - **Pipe read mocking**: Use `allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")` instead of raising exceptions
  - **Stdin wait_readable**: Use `allow(stdin).to receive(:wait_readable).and_return(nil)` for flush_stdin calls

- **Test isolation**: Terminal setup must be mocked/skipped in unit tests
  - `initialize` test marked as pending (requires actual terminal)
  - Use `allocate` + `instance_variable_set` pattern to create test instances without calling initialize
  - Integration/manual tests needed for actual terminal interaction

- **String mutability in tests**: Critical for input buffer testing
  - Use `String.new("text")` instead of frozen string literals (`"text"`)
  - Required because implementation uses `.insert!` and `.slice!` which modify in place
  - Example: `console.instance_variable_set(:@input_buffer, String.new("hello"))`

- **Thread safety testing**: Concurrent puts() calls validated thread safety
  - Use 100 threads to stress test the queue and mutex synchronization
  - Background threads in tests may fail if mocks not set up correctly
  - Tests can hang if IO.select mocks aren't configured properly

### Rubocop Configuration Decisions
- **Metrics chosen**:
  - `MethodLength: 25` - Adequate for console I/O logic
  - `ClassLength: 250` - Reasonable for unified console class
  - `BlockLength` excluded for specs (test blocks often longer)

- **Fiber scheduler compatibility**:
  - Use `@stdin.wait_readable(0)` instead of `IO.select([@stdin], nil, nil, 0)`
  - Rubocop warning: `Lint/IncompatibleIoSelectWithFiberScheduler`

- **Style preferences**:
  - `char.ord.between?(32, 126)` preferred over `char.ord >= 32 && char.ord <= 126`
  - Rescue modifier avoided: use begin/rescue block instead

### Architectural Patterns
- **Output queue signaling**: Pipe-based wake-up mechanism
  - `puts()` writes "x" to pipe to wake select loop
  - `drain_output_queue` reads from pipe to clear signals
  - Rescue `StandardError` in puts() to handle closed pipe gracefully

- **Spinner in separate thread**:
  - Spinner runs in background thread with own select loop
  - Checks for both output and Ctrl-C every 100ms
  - Must call `flush_stdin` when transitioning between modes

- **Cursor positioning**: Simple arithmetic works for Phase 1
  - Formula: `prompt.length + @cursor_pos + 1` (1-indexed)
  - ANSI escape: `\e[#{col}G` moves to column
  - No complex width calculations needed (yet)

### Known Issues / Future Work
- **Terminal cleanup reliability**:
  - `at_exit` hook ensures cleanup on normal exit
  - May need additional signal handling for robustness
  - SIGTERM and other signals should restore terminal state

- **Input buffer limitations**:
  - Currently single-line only (Phase 1 scope)
  - No cursor movement within line (Phase 2)
  - No line wrapping handling (future enhancement)
  - Long lines will wrap naturally but buffer keeps full text

- **Test hanging prevention**:
  - IO.select in tests requires proper mocking or tests will hang
  - Use timeouts in test runs to catch infinite loops
  - Background threads must be properly cleaned up in test teardown

### Dependencies
- **Ruby stdlib only**:
  - `io/console` for raw mode
  - `IO.select` for multiplexing
  - `Queue` for thread-safe output
  - `Mutex` for stdout synchronization

- **No external gems needed** for console functionality

### Performance Considerations
- **Select timeout**: 100ms for spinner animation (10 FPS)
- **Queue overhead**: Minimal - Queue is Ruby stdlib, highly optimized
- **Mutex contention**: Only on stdout writes, very brief critical sections
- **Pipe overhead**: Negligible - single byte writes for signaling

### Files Created/Modified
- `lib/nu/agent/console_io.rb` (349 lines) - Main implementation
- `spec/nu/agent/console_io_spec.rb` (297 lines) - Test suite with 26 examples
- `.rubocop.yml` - Code quality configuration
- `Gemfile` - Added rubocop dependency
- `lib/nu/agent.rb` - Required console_io

### Test Results
- **26 examples, 0 failures, 1 pending**
- Pending test: `#initialize` (requires actual terminal)
- All tests pass Rubocop with 0 offenses
- Thread safety validated with 100 concurrent threads
- All Phase 1 core features fully tested

### TDD Success Metrics
- ✅ Tests written before implementation
- ✅ All implementation code passes tests
- ✅ All code passes Rubocop
- ✅ Comprehensive coverage of Phase 1 features
- ✅ Test suite runs in <1 second (0.25s)
- ✅ No flaky tests - deterministic results
