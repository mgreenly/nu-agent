# TUI Troubleshooting Guide

## Issue: Keystrokes don't appear in input window

If you're experiencing this issue, let's debug it step by step.

### Step 1: Run the simple debug test

```bash
ruby test_tui_debug.rb
```

This minimal test will:
- Show what characters are being received from the keyboard
- Display them on screen so you can see if getch is working
- Help identify if it's an input or display issue

**What to look for:**
- When you type a character, do you see "Received: ..." update at the bottom?
- Does the character appear after the `>` prompt?
- What class is shown? (String or Integer?)

### Step 2: Check terminal compatibility

Some terminals have issues with ncurses. Try:

```bash
# Check TERM setting
echo $TERM

# Try setting it explicitly
export TERM=xterm-256color
ruby test_tui_debug.rb
```

### Step 3: Check curses gem version

```bash
gem list curses
```

Should show: `curses (1.5.3)` or similar

### Step 4: Test the full TUI

```bash
ruby test_tui.rb
```

### Common Issues and Fixes

#### Issue: Characters appear but disappear immediately
**Cause**: Window refresh timing
**Fix**: Already implemented - we call refresh after each input

#### Issue: Backspace doesn't work
**Cause**: Terminal sends different backspace codes
**Fix**: We handle 127, 8, and KEY_BACKSPACE

#### Issue: Arrow keys don't work
**Cause**: keypad() not enabled
**Fix**: We call `@input_win.keypad(true)`

#### Issue: "Not a TTY" error
**Cause**: Input/output is piped
**Fix**: Don't pipe input:
```bash
# Bad
echo "test" | ruby test_tui.rb

# Good
ruby test_tui.rb
```

#### Issue: Characters are strings instead of integers
**Cause**: Different curses implementations
**Fix**: Our code now handles both (check `readline` method)

### Debug Output

If test_tui_debug.rb shows keystrokes are being received, but test_tui.rb doesn't:
1. The issue is with the TUIManager window setup
2. Check that windows aren't overlapping incorrectly
3. Verify cursor is in the input window

### Still having issues?

Create a minimal reproduction:
1. Run test_tui_debug.rb and note what happens
2. Check your terminal emulator (xterm, gnome-terminal, iTerm2, etc.)
3. Try a different terminal emulator
4. Check if SSH is involved (some SSH clients have ncurses issues)

### Platform-Specific Notes

**Linux:** Usually works fine with most terminals
**macOS:** May need to install ncurses via homebrew
**Windows/WSL:** May have terminal compatibility issues

### Reporting Issues

If you find a bug, please include:
1. Output of `echo $TERM`
2. Terminal emulator name and version
3. Ruby version (`ruby --version`)
4. Curses gem version (`gem list curses`)
5. What test_tui_debug.rb shows when you type
6. Operating system and version
