# Proposal: Real-Time Progress Bar Support in ConsoleIO

**Status:** Proposed (Not Yet Implemented)
**Created:** 2025-10-30
**GitHub Issue:** [#25](https://github.com/mgreenly/nu-agent/issues/25)
**Related Issue:** Backup Command Progress Display (completed with compromise)
**Complexity:** Medium - Requires ConsoleIO architectural enhancement

## Problem Statement

### Current Behavior
When synchronous commands execute (like `/backup`), all output is buffered by ConsoleIO's queue system and only displayed when control returns to the readline select loop. This means progress updates during long-running operations appear all at once after completion, rather than in real-time.

**Example - Current Output Pattern:**
```
> /backup
[7 second pause with no feedback]
Copying database... (5.0 MB)
  Progress: 19% (1.0 MB / 5.0 MB)
  Progress: 39% (2.0 MB / 5.0 MB)
  Progress: 59% (3.0 MB / 5.0 MB)
  Progress: 79% (4.0 MB / 5.0 MB)
  Progress: 99% (5.0 MB / 5.0 MB)
  Progress: 100% (5.0 MB / 5.0 MB)
Backup created successfully:
  Path: ./memory-2025-10-30-142706.db
  Size: 5.0 MB
  Time: 2025-10-30 14:27:11
>
```

All progress lines appear instantly after the operation completes.

### Why This Happens

ConsoleIO uses a queued output architecture for thread safety and terminal state management:

1. **Output Queue:** `console.puts(text)` queues messages
2. **Select Loop:** Only the readline select loop drains the queue
3. **Synchronous Execution:** During command execution, we're NOT in the select loop
4. **Result:** All queued output displays at once when readline resumes

**Relevant Code:**
- `lib/nu/agent/console_io.rb:50-56` - `puts()` method queues output
- `lib/nu/agent/console_io.rb:455-479` - `handle_output_for_input_mode()` drains queue
- `lib/nu/agent/application.rb:196-217` - REPL loop with readline

## Compromise Solution (Currently Merged)

The backup command was implemented with a **compromise approach**:
- Progress updates use the normal queued output system
- Updates happen every 1 MB during file copy
- All progress information IS captured and displayed
- But appears after completion rather than in real-time

**Why This Was Acceptable:**
- Feature is functional
- No architectural changes required
- 98.91% test coverage maintained
- Suitable for database files under 10-20 MB
- Users see detailed progress information (just not live)

**Code Location:**
- `lib/nu/agent/commands/backup_command.rb:196-242` - Progress implementation

## Proposed Solution: Real-Time Progress Mode

Add a new mode to ConsoleIO that allows immediate, in-place progress updates similar to the existing spinner mode but designed for controlled progress bars.

### Desired User Experience

**Example - Proposed Real-Time Output:**
```
> /backup
Copying database... (5.0 MB)
[===>      ] 39% (2.0 MB / 5.0 MB)    [updates in-place every 100ms]
[=========>] 99% (5.0 MB / 5.0 MB)    [final update]
Backup created successfully:
  Path: ./memory-2025-10-30-142706.db
  Size: 5.0 MB
  Time: 2025-10-30 14:27:11
>
```

Progress bar updates in real-time on a single line using carriage returns.

### Technical Design

#### 1. Add Progress Bar Mode to ConsoleIO

Add three new public methods to `ConsoleIO`:

```ruby
# Start progress bar mode - displays initial line
# @param label [String] Initial text to display (e.g., "Copying database...")
def start_progress_bar(label)
  @mode = :progress_bar
  @mutex.synchronize do
    @stdout.write("#{label}\r\n")
    @stdout.flush
  end
end

# Update progress bar (in-place update on current line)
# @param text [String] Complete progress line (e.g., "[===>  ] 45% (2.1 MB / 5.0 MB)")
def update_progress_bar(text)
  return unless @mode == :progress_bar

  @mutex.synchronize do
    @stdout.write("\r\e[2K#{text}")  # Clear line, write progress
    @stdout.flush
  end
end

# End progress bar - move to next line
def end_progress_bar
  @mode = :input
  @mutex.synchronize do
    @stdout.write("\r\n")  # Keep final progress visible, move to next line
    @stdout.flush
  end
end
```

#### 2. Mode State Management

Add `:progress_bar` to the mode enum:
- Current modes: `:input`, `:spinner`
- New mode: `:progress_bar`

Progress bar mode characteristics:
- Direct stdout writes (like spinner)
- Mutex-protected for thread safety
- Updates are immediate (not queued)
- In-place updates using `\r` (carriage return)

#### 3. Integration Pattern

Commands use progress bars like this:

```ruby
# In BackupCommand or other long-running commands
def copy_with_progress(source, destination)
  file_size = File.size(source)

  # Start progress
  app.console.start_progress_bar("Copying database... (#{format_bytes(file_size)})")

  bytes_copied = 0
  update_interval = 102_400  # Update every 100 KB
  last_update = 0

  begin
    File.open(source, "rb") do |input|
      File.open(destination, "wb") do |output|
        while (chunk = input.read(8192))
          output.write(chunk)
          bytes_copied += chunk.size

          if bytes_copied - last_update >= update_interval || bytes_copied == file_size
            # Real-time update
            percent = (bytes_copied.to_f / file_size * 100).to_i
            bar = build_progress_bar(bytes_copied, file_size)
            app.console.update_progress_bar("[#{bar}] #{percent}% (#{format_bytes(bytes_copied)} / #{format_bytes(file_size)})")
            last_update = bytes_copied
          end
        end
      end
    end
  ensure
    # Always end progress mode
    app.console.end_progress_bar
  end
end
```

#### 4. Handling Background Output

What happens if background threads output during progress mode?

**Option A: Queue During Progress (Simpler)**
- Background output still goes to queue
- Gets drained when progress ends
- Progress bar is never interrupted

**Option B: Interrupt Progress (More Complex)**
- Background output clears progress line
- Displays the message
- Redraws progress line below
- Similar to how spinner handles output (see `handle_output_for_spinner_mode`)

Recommendation: Start with Option A, add Option B if needed.

#### 5. Edge Cases to Handle

1. **Ctrl-C during progress:**
   - Ensure progress mode is ended
   - Clean up progress line
   - Similar to spinner's Interrupt handling

2. **Error during progress:**
   - Use `begin/ensure` to guarantee `end_progress_bar` is called
   - Progress line should be cleared or completed

3. **Very fast operations:**
   - If operation completes in <100ms, may not see updates
   - This is acceptable behavior

4. **Terminal width:**
   - Progress bars should respect terminal width
   - Consider truncating or wrapping long file paths

## Implementation Plan

### Phase 1: Core Progress Mode (2-3 hours)
1. Add three progress methods to ConsoleIO
2. Add `:progress_bar` mode handling
3. Write comprehensive tests for ConsoleIO progress methods
4. Verify mode transitions (input → progress_bar → input)

**Files to Modify:**
- `lib/nu/agent/console_io.rb`
- `spec/nu/agent/console_io_spec.rb`

### Phase 2: BackupCommand Integration (1 hour)
1. Update `BackupCommand#copy_with_progress` to use new methods
2. Update progress bar to use in-place updates (100 KB intervals)
3. Update BackupCommand tests
4. Manual testing with various file sizes

**Files to Modify:**
- `lib/nu/agent/commands/backup_command.rb`
- `spec/nu/agent/commands/backup_command_spec.rb`

### Phase 3: Background Output Handling (1-2 hours, optional)
1. Implement Option B if needed (interrupt-based output)
2. Add tests for background output during progress
3. Handle Ctrl-C gracefully

### Phase 4: Documentation & Polish (30 min)
1. Update BackupCommand documentation
2. Add examples to help text if needed
3. Update this proposal to "Implemented" status

**Total Estimated Time:** 4-6 hours

## Testing Strategy

### Unit Tests (ConsoleIO)
- `start_progress_bar` sets mode and outputs initial line
- `update_progress_bar` writes with carriage return
- `end_progress_bar` moves to next line and resets mode
- Mode transitions work correctly
- Mutex protection prevents concurrent write issues

### Integration Tests (BackupCommand)
- Progress updates happen during file copy (mock time/IO)
- Progress reaches 100%
- Progress bar clears on completion
- Progress bar clears on error (ensure block)
- Console methods are called in correct order

### Manual Testing
- Small files (<1 MB): No progress bar
- Medium files (2-5 MB): Progress updates visible
- Large files (>10 MB): Smooth progress updates
- Ctrl-C during backup: Clean termination
- Error during backup: Progress cleaned up

## Alternative Approaches Considered

### 1. Background Thread for Progress
Spawn a separate thread to update progress while main thread copies.

**Pros:**
- Decouples progress from copy logic

**Cons:**
- More complex thread coordination
- Risk of race conditions
- Harder to test
- Still needs ConsoleIO support

**Verdict:** Rejected - More complex with no clear benefit

### 2. Async I/O with EventMachine/Async
Use non-blocking I/O for file operations.

**Pros:**
- "Ruby way" for async operations
- Could handle multiple concurrent operations

**Cons:**
- Major architectural change
- Significant dependencies
- Overkill for this use case

**Verdict:** Rejected - Too much complexity

### 3. Periodic Polling Thread
Separate thread polls file size periodically during copy.

**Pros:**
- Decouples progress from copy
- Simple to implement

**Cons:**
- File size polling can be slow on some filesystems
- Still needs ConsoleIO real-time support
- More complex for marginal benefit

**Verdict:** Rejected - Doesn't solve core ConsoleIO issue

## Success Criteria

When this feature is complete:

1. ✅ Progress bar updates in real-time during file operations
2. ✅ Progress bar displays on a single line (in-place updates)
3. ✅ ConsoleIO has documented progress bar mode
4. ✅ BackupCommand shows live progress for files >1 MB
5. ✅ All tests pass with >98% coverage
6. ✅ No lint violations
7. ✅ Manual testing confirms smooth visual updates
8. ✅ Error handling ensures progress is always cleaned up

## Future Enhancements (Beyond This Proposal)

- **Spinner + Progress Hybrid:** Show spinner animation alongside percentage
- **Time Estimates:** Display "2 seconds remaining" based on transfer rate
- **Transfer Speed:** Show "5.2 MB/s" during copy
- **Colored Progress Bars:** Use ANSI colors for filled/unfilled portions
- **Multi-line Progress:** Support multiple concurrent progress bars (like npm)
- **Progress Bar Component:** Reusable progress bar helper class

## References

- ConsoleIO Implementation: `lib/nu/agent/console_io.rb`
- Spinner Mode: `lib/nu/agent/console_io.rb:87-623` (existing pattern to follow)
- BackupCommand: `lib/nu/agent/commands/backup_command.rb`
- GitHub Issue #9: Original backup command specification
- Plan Document: `backup-command-plan.md` (shows completed phases)

## Notes for Future Implementation

- Start by studying the spinner mode implementation - it's a good template
- The mutex handling in `update_progress_bar` is critical for thread safety
- Remember to handle raw terminal mode (`\r\n` not just `\n`)
- Test with both fast and slow file operations
- Consider using a simple state machine for mode transitions
- Don't forget to flush stdout after every write

---

**Status:** This proposal is ready for implementation as a new GitHub issue. The compromise solution (buffered progress output) has been merged and is functional. This enhancement would improve user experience for long-running operations but is not blocking any functionality.
