# Phase 3.5 Progress Tracker

**Last Updated**: 2025-10-26
**Status**: ⚙️ IN PROGRESS (~60% complete)

## Quick Summary

We're migrating from the old TUI system (TUIManager/OutputManager/OutputBuffer) to the new ConsoleIO system. Application.rb is done, Formatter.rb is partially done.

## ✅ Completed (60%)

### Application.rb - COMPLETE ✅
- [x] ConsoleIO initialization
- [x] `output_line()` and `output_lines()` helpers
- [x] All spinner calls (show/hide)
- [x] REPL loop simplified
- [x] Integration tests written and passing
- [x] File: `lib/nu/agent/application.rb`
- [x] Tests: `spec/nu/agent/application_console_integration_spec.rb` (11 examples, 0 failures)

### Formatter.rb - 40% COMPLETE ⚙️
- [x] `initialize()` signature updated
- [x] All spinner calls updated
- [x] `display_assistant_message()` migrated
- [x] Token stats output migrated
- [ ] **REMAINING**: ~9 methods still use OutputBuffer (see below)

## ❌ Remaining Work (40%)

### 1. Complete Formatter.rb Migration (HIGHEST PRIORITY)

**Pattern to apply to each method**:
```ruby
# BEFORE:
buffer = OutputBuffer.new
buffer.add("text")           # or .debug() or .error()
@output_manager&.flush_buffer(buffer)

# AFTER:
@console.puts("text")                              # normal
@console.puts("\e[90mtext\e[0m") if @debug        # debug (gray)
@console.puts("\e[31mtext\e[0m")                  # error (red)
```

**Methods still needing conversion** (in `lib/nu/agent/formatter.rb`):
- [ ] `display_token_summary()` - Line 94
- [ ] `display_thread_event()` - Line 105
- [ ] `display_message_created()` - Line 120
- [ ] `display_llm_request()` - Line 206
- [ ] `display_system_message()` - Line 309
- [ ] `display_spell_checker_message()` - Line 346
- [ ] `display_tool_call()` - Line 357
- [ ] `display_tool_result()` - Line 407
- [ ] `display_error()` - Line 477

**Reference**: See `display_assistant_message()` (line 267) for a completed example.

### 2. Clean Up Application.rb
- [ ] Remove `setup_readline()` method (no longer used)
- [ ] Remove `save_history()` method (no longer used)
- [ ] Remove `@output` initialization (after Formatter is done)

### 3. Remove --tui Flag
- [ ] Edit `lib/nu/agent/options.rb`
- [ ] Remove the `--tui` option

### 4. Update Requires
- [ ] Edit `lib/nu/agent.rb`
- [ ] Remove: `require_relative 'agent/tui_manager'`
- [ ] Remove: `require_relative 'agent/output_manager'`
- [ ] Remove: `require_relative 'agent/output_buffer'`

### 5. Delete Legacy Files (LAST STEP)
- [ ] `lib/nu/agent/tui_manager.rb`
- [ ] `lib/nu/agent/output_manager.rb`
- [ ] `lib/nu/agent/output_buffer.rb`

### 6. Final Testing
- [ ] Run: `bundle exec rspec` (all tests should pass)
- [ ] Run: `bundle exec rubocop` on modified files
- [ ] Manual test: `bundle exec nu-agent`
- [ ] Verify slash commands work (/help, /debug, etc.)
- [ ] Verify spinner works during processing
- [ ] Verify Ctrl-C works cleanly
- [ ] Verify background threads can output safely

## Files Modified So Far

- ✅ `lib/nu/agent/application.rb` - ConsoleIO integrated
- ⚙️ `lib/nu/agent/formatter.rb` - Partially migrated
- ✅ `spec/nu/agent/application_console_integration_spec.rb` - New test file

## Test Status

- ✅ ConsoleIO tests: 70 examples, 0 failures
- ✅ Application integration tests: 11 examples, 0 failures
- ⚠️ Full suite: Likely failing due to incomplete Formatter migration

## Next Steps

1. **Start here**: Complete Formatter.rb migration (9 methods remaining)
2. Use TDD: Update one method, run tests, repeat
3. Run `bundle exec rspec spec/nu/agent/application_console_integration_spec.rb` after each change
4. Once Formatter is done, run full test suite
5. Clean up legacy code
6. Final testing

## Useful Commands

```bash
# Run integration tests
bundle exec rspec spec/nu/agent/application_console_integration_spec.rb

# Run all ConsoleIO tests
bundle exec rspec spec/nu/agent/console_io_spec.rb

# Run full test suite (once complete)
bundle exec rspec

# Check formatting
bundle exec rubocop lib/nu/agent/application.rb lib/nu/agent/formatter.rb

# Manual test
bundle exec nu-agent
```

## Notes

- The new system is SIMPLER than the old one
- Direct console.puts() is cleaner than buffer → flush → write
- ANSI colors for debug/error replace buffer metadata
- All tests use strict TDD approach (red → green → refactor)
- Don't delete legacy files until everything works!
