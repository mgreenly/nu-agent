# TUI (Terminal User Interface) Usage

## Overview

The TUI mode provides a split-pane interface that separates output from input, preventing them from interfering with each other. This is especially useful when background workers (summarizer, man indexer) are producing output.

## Enabling TUI Mode

Run nu-agent with the `--tui` flag:

```bash
nu-agent --tui
```

Or with debug mode:

```bash
nu-agent --tui --debug
```

## Layout

```
┌─────────────────────────────────────┐
│                                     │
│  [Output Pane - 80% of screen]     │ ← All program output appears here
│  - LLM responses                    │   - Scrolls independently
│  - Debug messages (when enabled)    │   - Keeps history (1000 lines)
│  - Error messages                   │   - Thread-safe
│  - Background worker output         │
│                                     │
│                                     │
├─────────────────────────────────────┤ ← Separator line
│ > your input here_                  │ ← Input Pane (20% of screen)
│                                     │   - Readline-like editing
│                                     │   - Arrow keys, Home/End work
└─────────────────────────────────────┘
```

## Features

### Output Pane (Top 80%)
- **Scrollable**: Automatically scrolls as new output appears
- **Colored**: Errors in red, debug in gray (dim), normal in white
- **Thread-safe**: Multiple background threads can write simultaneously
- **Scrollback**: Keeps last 1000 lines of output
- **ANSI-aware**: Strips ANSI color codes (uses ncurses colors instead)

### Input Pane (Bottom 20%)
- **Line editing**: Type naturally with cursor movement
- **Arrow keys**: Left/Right to move cursor
- **Home/End**: Jump to start/end of line
- **Backspace/Delete**: Edit text
- **Ctrl-C**: Exit program
- **Ctrl-D**: Exit program (when input empty)

### Keyboard Controls

- **Enter**: Submit input
- **Backspace**: Delete character before cursor
- **Delete**: Delete character at cursor
- **←/→**: Move cursor left/right
- **Home**: Move to start of line
- **End**: Move to end of line
- **Ctrl-C**: Exit program
- **Ctrl-D**: Exit (when input empty)

## Thread Safety

The TUI uses mutex locks to ensure atomic writes:
- Each complete message is written as a transaction
- Prevents interleaving from orchestrator, summarizer, man indexer threads
- Output → buffer → refresh happens atomically

## Fallback Behavior

If TUI initialization fails (terminal too small, not a TTY, etc.), the application automatically falls back to standard mode with a warning message:

```
Warning: Failed to initialize TUI: Terminal too small (minimum 10x40)
Falling back to standard mode
```

## Minimum Requirements

- **Terminal size**: 10 rows × 40 columns minimum
- **TTY**: Must be a real terminal (not piped)
- **TERM**: Must support ncurses

## Testing TUI

A standalone test script is available:

```bash
ruby test_tui.rb
```

This demonstrates:
- TUI initialization
- Output to output pane
- Different color modes (normal, debug, error)
- Input from input pane
- Clean shutdown

## Comparison with Standard Mode

| Feature | Standard Mode | TUI Mode |
|---------|--------------|----------|
| Output location | stdout | Output pane |
| Input location | stdin | Input pane |
| Spinner | Yes | No (unnecessary) |
| Scrollback | Terminal dependent | 1000 lines |
| Background output | Interrupts input | Separate pane |
| Readline history | File-based | Session only |
| Colors | ANSI codes | ncurses colors |

## Implementation Details

### Files Modified/Created

- `lib/nu/agent/tui_manager.rb` - New TUI manager class
- `lib/nu/agent/output_manager.rb` - Routes output to TUI when active
- `lib/nu/agent/application.rb` - Initializes TUI, uses TUI readline
- `lib/nu/agent/options.rb` - Added --tui flag
- `lib/nu/agent.rb` - Require tui_manager
- `nu-agent.gemspec` - Added curses dependency

### Key Classes

**TUIManager** (`lib/nu/agent/tui_manager.rb`)
- Manages ncurses windows and layout
- Provides thread-safe output methods
- Handles input with readline-like features
- Manages resize events

**OutputManager** (`lib/nu/agent/output_manager.rb`)
- Detects TUI mode and routes output accordingly
- Maintains compatibility with standard mode
- Disables spinner in TUI mode

## Troubleshooting

### "Terminal too small" error
Resize your terminal to at least 10 rows × 40 columns (24×80 recommended)

### "Not a TTY" error
Don't pipe input/output when using --tui:
```bash
# Bad
echo "test" | nu-agent --tui

# Good
nu-agent --tui
```

### Colors not working
Your terminal might not support ncurses colors. Try setting:
```bash
export TERM=xterm-256color
```

### TUI won't start
Check that curses gem is installed:
```bash
bundle install
gem list curses
```

## Future Enhancements

Potential improvements (not yet implemented):
- Status line showing background worker status
- Tab completion in TUI input pane
- Command history (up/down arrows)
- Search in output scrollback
- Copy/paste support
- Mouse support for scrolling
