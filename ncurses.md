# NCurses Split-Pane Interface

## Goal
Create a simple split-pane terminal UI using ncurses where:
- **Top 4/5 of screen**: Output pane (scrollable)
- **Bottom 1/5 of screen**: Input pane (readline-like)
- Both panes scroll independently
- Keep it as simple as possible

## Architecture

### New Class: `Nu::Agent::TUIManager`

Location: `lib/nu/agent/tui_manager.rb`

**Responsibilities:**
- Initialize ncurses windows (output pane + input pane)
- Manage output buffer (scrollback)
- Handle input with basic readline features
- Clean shutdown and terminal restoration
- Handle terminal resize events

### Integration Points

1. **OutputManager** (lib/nu/agent/output_manager.rb)
   - Detect if TUI mode is active
   - Route output through TUI instead of stdout
   - Keep spinner logic but adapt to TUI pane

2. **Application** (lib/nu/agent/application.rb)
   - Add `--tui` command line option
   - Initialize TUIManager when enabled
   - Pass TUI instance to OutputManager
   - Handle Ctrl-C gracefully to restore terminal

3. **Options** (lib/nu/agent/options.rb)
   - Add `tui` boolean flag

## Implementation Plan

### Phase 1: Basic TUI Manager

```ruby
class TUIManager
  def initialize
    @mutex = Mutex.new  # CRITICAL: For thread-safe output
    @output_buffer = []
    # Initialize curses
    # Create windows (output_win, input_win, separator)
    # Set up scrolling regions
  end

  def write_output(text)
    @mutex.synchronize do
      # Add complete message to output buffer
      # Update output window (atomic operation)
      # Refresh display
    end
  end

  def readline(prompt)
    # Show prompt in input pane
    # Get user input
    # Return line
  end

  def close
    # Restore terminal
    # Close curses
  end
end
```

### Phase 2: Integration

- Modify OutputManager to check for TUI
- Replace Readline with TUI input
- Route all output through TUI

### Phase 3: Polish

- Handle resize (SIGWINCH)
- Basic line editing (backspace, cursor movement)
- Visual separator between panes
- Status line (optional)

## Window Layout

```
┌─────────────────────────────────────┐
│                                     │ ← Output Pane (80%)
│  [LLM Output, Debug, Errors, etc.]  │   - Scrollable
│                                     │   - Shows all program output
│                                     │
│                                     │
│                                     │
│                                     │
│                                     │
├─────────────────────────────────────┤ ← Separator Line
│ > user input here_                  │ ← Input Pane (20%)
│                                     │   - Readline-like editing
│                                     │   - Prompt visible
└─────────────────────────────────────┘
```

## Curses Basics

### Key Functions
- `Curses.init_screen` - Initialize ncurses
- `Curses.newwin(height, width, y, x)` - Create window
- `win.setscrreg(top, bottom)` - Set scrolling region
- `win.scrollok(true)` - Enable scrolling
- `win.addstr(str)` - Add string
- `win.refresh` - Update display
- `Curses.close_screen` - Clean shutdown

### Color Support
```ruby
Curses.start_color
Curses.init_pair(1, Curses::COLOR_RED, Curses::COLOR_BLACK)
win.attron(Curses.color_pair(1)) { win.addstr("error") }
```

## Fallback Strategy

- Check if terminal supports curses: `ENV['TERM']` and `$stdout.tty?`
- Gracefully disable TUI if:
  - Not a TTY (piped output)
  - Terminal doesn't support curses
  - User doesn't pass `--tui` flag
- Fall back to current OutputManager behavior

## Thread Safety

**CRITICAL**: Output pane must use mutex to ensure atomic writes
- Each complete output (message, debug line, error) is written as a transaction
- Prevents interleaving from multiple threads (orchestrator, summarizer, man indexer)
- Reuse existing OutputManager mutex pattern
- Lock held during: format message → add to buffer → refresh window

```ruby
def write_output(text)
  @mutex.synchronize do
    # Add complete message to output buffer
    # Update output window
    # Refresh display
  end
end
```

## Edge Cases

1. **Terminal too small**: Minimum size check (e.g., 24x80)
2. **Resize during operation**: Handle SIGWINCH signal
3. **Output during input**: Output writes lock mutex, update pane, continue
4. **Long lines**: Wrap or truncate
5. **Ctrl-C**: Clean curses shutdown before exit
6. **Background threads**: Mutex ensures atomic output (see Thread Safety above)

## Testing Strategy

1. Test in normal terminal
2. Test with small terminal size
3. Test with background workers (summarizer, man indexer)
4. Test Ctrl-C and clean shutdown
5. Test resize events
6. Verify fallback to non-TUI mode works

## Files to Create/Modify

### New Files
- `lib/nu/agent/tui_manager.rb` - Main TUI class

### Modified Files
- `lib/nu/agent/options.rb` - Add --tui flag
- `lib/nu/agent/output_manager.rb` - TUI integration
- `lib/nu/agent/application.rb` - Initialize TUI, handle cleanup
- `lib/nu/agent.rb` - Require tui_manager
- `nu-agent.gemspec` - Already added curses dependency ✓

## Benefits

1. **Clean separation** - Output never interferes with input
2. **Better UX** - See background tasks without disruption
3. **Professional** - Looks like modern CLI tools
4. **Scrollback** - Review full output history
5. **Simple** - Minimal ncurses features, easy to maintain

## Alternatives Considered

1. **tmux/screen** - Requires external tools
2. **tty-* gems** - More complex, additional dependencies
3. **Terminal ANSI tricks** - Fragile, terminal-specific
4. **curses (chosen)** - Standard, simple, portable
