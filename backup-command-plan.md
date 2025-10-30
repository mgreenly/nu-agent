# Nu-Agent v0.17 Plan: Implement /backup Command

Last Updated: 2025-10-30
Target Version: 0.17.0
Plan Status: Draft for review
GitHub Issue: https://github.com/mgreenly/nu-agent/issues/9

## Index
- High-level motivation
- Scope (in)
- Scope (out, future enhancements)
- Key technical decisions
- Dependencies
- Implementation phases
  - Phase 1: Create BackupCommand with basic functionality
  - Phase 2: Add progress bar for large files
  - Phase 3: Integrate with BackgroundWorkerManager
  - Phase 4: Error handling and validation
  - Phase 5: Testing and refinement
- Success criteria
- Future enhancements
- Notes

## High-level motivation
- Provide users with a simple, safe way to create database backups
- Ensure database integrity during backup by pausing background workers and closing connections
- Show progress feedback for large database files (>1 MB)
- Support both default timestamped backups and custom destination paths
- Enable users to protect their conversation history and embeddings data

## Scope (in)
- Create `/backup` command with optional destination path argument
- Default backup location: `./memory-YYYY-MM-DD-HHMMSS.db` (current directory)
- Custom destination: `/backup /path/to/backup.db`
- Pause all background workers before backup
- Close database connections cleanly
- Copy database file with progress bar for files >1 MB
- Verify backup file exists and has correct size after copy
- Reopen database connections
- Resume background workers
- Display summary with backup path, file size, and timestamp
- Error handling for:
  - Missing database file
  - Insufficient disk space
  - Write permission issues
  - Copy operation failures
- Comprehensive test coverage (11 test cases from issue)

## Scope (out, future enhancements)
- Listing available backups (`/backup list`)
- Automatic backup scheduling
- Backup retention policies
- Restore command (`/backup restore`)
- Compression of backup files
- Incremental or differential backups
- Backup verification (checksums)
- Remote backup destinations (S3, etc.)
- Progress bar for files <1 MB (keep simple for small files)

## Key technical decisions

### Architecture
- Create `lib/nu/agent/commands/backup_command.rb` following BaseCommand pattern
- Use `BackgroundWorkerManager#pause_all` and `resume_all` for worker coordination
- Use `History#close` and re-initialization for database connection management
- Leverage Ruby's `FileUtils.cp` for file copying (similar to existing file_copy tool)
- Implement custom progress bar using `File.size` and chunked reading

### Naming and defaults
- Command: `/backup [destination]`
- Default filename format: `memory-YYYY-MM-DD-HHMMSS.db` (ISO 8601-like, filesystem-safe)
- Default location: Current working directory (`.`)
- Database path source: `@app.history.db_path` (typically `~/.nuagent/memory.db`)

### Progress bar
- Trigger: Files larger than 1 MB (1,048,576 bytes)
- Format: `[=========> ] 45% (6.8 MB / 15.2 MB)`
- Update frequency: Approximately every 100 KB copied
- Use ANSI escape codes for in-place updates (carriage return)
- Human-readable sizes (KB, MB, GB with 1 decimal place)

### Error handling strategy
- Pre-flight checks before pausing workers:
  - Verify source database file exists
  - Check destination directory exists (or can be created)
  - Check write permissions on destination directory
  - Estimate required disk space vs available space
- Abort early if any pre-flight check fails (don't pause workers unnecessarily)
- Use begin/ensure blocks to guarantee worker resume even on failure
- Provide clear, actionable error messages

### Database path access
- Application needs to expose database file path
- Add `db_path` method to History class if not already accessible
- Command accesses via `@app.history.db_path`

## Dependencies

### Required (from issue)
- Issue #5: Pausable Background Tasks ✓ COMPLETE
  - `BackgroundWorkerManager#pause_all` exists
  - `BackgroundWorkerManager#resume_all` exists
  - `BackgroundWorkerManager#wait_until_all_paused(timeout)` exists
  - All workers inherit from `PausableTask`

### Verified existing infrastructure
- Database connection management via `History#close` (lib/nu/agent/history.rb:375-391)
- Command pattern via `BaseCommand` (lib/nu/agent/commands/base_command.rb)
- Command registration in Application (lib/nu/agent/application.rb:149-163)
- File utilities pattern via `FileCopy` tool (lib/nu/agent/tools/file_copy.rb)
- Output helper: `@app.output_line(text, type: :normal|:debug|:error)`

## Implementation phases

### Phase 1: Create BackupCommand with basic functionality (2 hrs)

**Goal**: Implement working `/backup` command with default and custom paths (no progress bar yet).

**Tasks**:
1. Create `lib/nu/agent/commands/backup_command.rb`:
   - Inherit from `BaseCommand`
   - Parse optional destination argument
   - Generate default filename with timestamp
   - Validate destination path (parent directory exists or can be created)
   - Return success message with path and size

2. Add database path accessor to History class:
   - Verify `@db_path` is accessible (check constructor in history.rb:8-24)
   - Add `attr_reader :db_path` if needed

3. Implement basic backup flow (no progress bar):
   - Get source path from `@app.history.db_path`
   - Generate/validate destination path
   - Pre-flight checks (source exists, destination writable)
   - Pause workers: `@app.worker_manager.pause_all`
   - Wait for pause: `@app.worker_manager.wait_until_all_paused(5.0)`
   - Close database: `@app.history.close`
   - Copy file: `FileUtils.cp(source, destination)`
   - Verify backup: Check `File.exist?(destination)` and `File.size(destination)`
   - Reopen database: Re-initialize History object
   - Resume workers: `@app.worker_manager.resume_all`
   - Display success message

4. Register command in `application.rb`:
   - Add `require_relative "commands/backup_command"` if needed
   - Add `@command_registry.register("/backup", Commands::BackupCommand)` to `register_commands`

**Testing**:
- Manual test: `/backup` creates timestamped backup in current directory
- Manual test: `/backup ~/test-backup.db` creates backup at custom path
- Verify backup file size matches original
- Verify application continues working after backup

### Phase 2: Add progress bar for large files (1.5 hrs)

**Goal**: Show progress feedback when copying files >1 MB.

**Tasks**:
1. Implement progress bar helper method in BackupCommand:
   ```ruby
   def copy_with_progress(source, destination, threshold: 1_048_576)
     file_size = File.size(source)

     if file_size < threshold
       FileUtils.cp(source, destination)
       return
     end

     # Show progress bar for large files
     bytes_copied = 0
     update_interval = 102_400 # 100 KB
     last_update = 0

     File.open(source, 'rb') do |input|
       File.open(destination, 'wb') do |output|
         while (chunk = input.read(8192)) # 8 KB chunks
           output.write(chunk)
           bytes_copied += chunk.size

           if bytes_copied - last_update >= update_interval || bytes_copied == file_size
             display_progress(bytes_copied, file_size)
             last_update = bytes_copied
           end
         end
       end
     end

     # Clear progress line
     print "\r" + " " * 80 + "\r"
   end

   def display_progress(current, total)
     percent = (current.to_f / total * 100).to_i
     bar_width = 10
     filled = (bar_width * current / total).to_i
     bar = "=" * filled + ">" + " " * (bar_width - filled - 1)

     current_mb = format_bytes(current)
     total_mb = format_bytes(total)

     print "\r[#{bar}] #{percent}% (#{current_mb} / #{total_mb})"
   end

   def format_bytes(bytes)
     if bytes < 1024
       "#{bytes} B"
     elsif bytes < 1_048_576
       "#{(bytes / 1024.0).round(1)} KB"
     elsif bytes < 1_073_741_824
       "#{(bytes / 1_048_576.0).round(1)} MB"
     else
       "#{(bytes / 1_073_741_824.0).round(1)} GB"
     end
   end
   ```

2. Replace `FileUtils.cp` with `copy_with_progress` in backup flow

**Testing**:
- Create test database >1 MB (add dummy data if needed)
- Verify progress bar displays during copy
- Verify progress bar updates approximately every 100 KB
- Verify progress bar reaches 100%
- Verify progress bar clears after completion
- Test with files <1 MB (should not show progress bar)

### Phase 3: Integrate with BackgroundWorkerManager (1 hr)

**Goal**: Ensure proper coordination with background workers and database lifecycle.

**Tasks**:
1. Add database re-initialization logic:
   - After backup, cannot simply call `@app.history.close` and continue
   - Need to create new History instance and update application state
   - Add helper method to Application class:
     ```ruby
     def reopen_database
       @history&.close
       @history = History.new
       # Re-initialize any components that depend on history
       # Workers already have reference, may need to update
     end
     ```

2. Update backup flow to use new helper:
   - Close: `@app.history.close`
   - Copy: `copy_with_progress(source, destination)`
   - Reopen: `@app.reopen_database`

3. Test worker interaction:
   - Verify workers actually pause before backup
   - Verify workers resume after backup
   - Test backup while workers are actively processing
   - Verify no data corruption or race conditions

**Testing**:
- Start multiple workers processing data
- Execute `/backup` mid-operation
- Verify workers pause (check `/worker <name> status`)
- Verify backup completes successfully
- Verify workers resume and continue processing
- Check conversation history is intact after backup

### Phase 4: Error handling and validation (1.5 hrs)

**Goal**: Implement robust error handling and helpful error messages.

**Tasks**:
1. Implement pre-flight validation checks:
   ```ruby
   def validate_backup
     # Check source exists
     return error("Database file not found: #{source_path}") unless File.exist?(source_path)

     # Check source is readable
     return error("Cannot read database file") unless File.readable?(source_path)

     # Check/create destination directory
     dest_dir = File.dirname(destination_path)
     unless Dir.exist?(dest_dir)
       begin
         FileUtils.mkdir_p(dest_dir)
       rescue StandardError => e
         return error("Cannot create destination directory: #{e.message}")
       end
     end

     # Check destination is writable
     return error("Destination directory is not writable") unless File.writable?(dest_dir)

     # Check disk space
     source_size = File.size(source_path)
     available_space = get_available_space(dest_dir)
     if available_space && available_space < source_size
       return error("Insufficient disk space (need #{format_bytes(source_size)}, have #{format_bytes(available_space)})")
     end

     nil # No errors
   end

   def get_available_space(path)
     # Use df command to check available space
     result = `df -B1 #{Shellwords.escape(path)} 2>/dev/null | tail -1 | awk '{print $4}'`
     result.strip.to_i
   rescue StandardError
     nil # Return nil if cannot determine space
   end
   ```

2. Add begin/ensure block to guarantee worker resume:
   ```ruby
   def execute(input)
     error_result = validate_backup
     return error_result if error_result

     pause_workers_and_database

     begin
       copy_with_progress(source_path, destination_path)
       verify_backup
       display_success
     rescue StandardError => e
       error("Backup failed: #{e.message}")
     ensure
       resume_workers_and_database
     end

     :continue
   end
   ```

3. Implement verification:
   ```ruby
   def verify_backup
     unless File.exist?(destination_path)
       raise "Backup file was not created"
     end

     source_size = File.size(source_path)
     dest_size = File.size(destination_path)

     unless source_size == dest_size
       raise "Backup file size mismatch (expected #{source_size}, got #{dest_size})"
     end
   end
   ```

**Testing**:
- Test with non-existent database file
- Test with read-only destination directory
- Test with insufficient disk space (mock/simulate)
- Test with invalid destination path
- Test worker resume after failure (simulate copy failure)
- Verify application remains stable after backup failures

### Phase 5: Testing and refinement (2 hrs)

**Goal**: Comprehensive test coverage and final polish.

**Tasks**:
1. Create `spec/nu/agent/commands/backup_command_spec.rb`:
   - Test default timestamp format (matches `YYYY-MM-DD-HHMMSS` pattern)
   - Test custom destination path
   - Test progress bar shows for files >1 MB
   - Test no progress bar for files <1 MB
   - Test backup file verification (existence and size)
   - Test workers pause before backup
   - Test workers resume after backup
   - Test database connections close/reopen
   - Test error: source file missing
   - Test error: insufficient permissions
   - Test error: insufficient disk space
   - Test application stability after backup
   - Mock BackgroundWorkerManager, History, FileUtils
   - Use time-freezing for timestamp tests

2. Update help text:
   - Add `/backup` command to HelpCommand output
   - Include description: "Create a backup of the conversation database"
   - Include usage examples:
     - `/backup` - Creates memory-YYYY-MM-DD-HHMMSS.db in current directory
     - `/backup ~/backups/memory-backup.db` - Creates backup at specified path

3. Add command documentation:
   - Document in code comments
   - Add inline help for `/backup help` if applicable

4. Manual testing scenarios:
   - Backup during active conversation
   - Backup with workers running
   - Backup with large database (>10 MB)
   - Backup to various destinations (relative/absolute paths)
   - Backup with special characters in path
   - Restore from backup (manual file copy) and verify integrity

**Testing**:
- Run full test suite: `rake test`
- Check coverage: `rake coverage:enforce` (must pass)
- Run linter: `rake lint` (no violations)
- Manual testing per scenarios above
- Verify no regressions in existing functionality

## Success criteria

### Functional requirements
- ✓ `/backup` creates timestamped backup in current directory
- ✓ `/backup /path/to/file.db` creates backup at specified location
- ✓ Timestamp format matches `YYYY-MM-DD-HHMMSS`
- ✓ Progress bar shows for files >1 MB
- ✓ Progress bar updates ~every 100 KB
- ✓ No progress bar for files ≤1 MB
- ✓ Backup file verified (exists and correct size)
- ✓ Workers pause before backup
- ✓ Workers resume after backup
- ✓ Database connections cleanly closed/reopened
- ✓ Application remains stable after backup

### Error handling
- ✓ Aborts if database file missing
- ✓ Aborts if destination not writable
- ✓ Aborts if insufficient disk space
- ✓ Aborts if copy operation fails
- ✓ Workers always resume (even on failure)
- ✓ Clear, actionable error messages

### Code quality
- ✓ All tests pass (`rake test`)
- ✓ Coverage requirements met (`rake coverage:enforce`)
- ✓ No RuboCop violations (`rake lint`)
- ✓ Follows existing command pattern
- ✓ Well-documented code
- ✓ Comprehensive test coverage (11+ test cases)

### User experience
- ✓ Simple command syntax
- ✓ Clear success/failure messages
- ✓ Progress feedback for large files
- ✓ Fast operation for small files
- ✓ Minimal disruption to active work
- ✓ Help text includes examples

## Future enhancements

### Backup management
- `/backup list` - Show available backups with size and date
- `/backup list --sort=date|size` - Sort backup list
- `/backup clean --keep=N` - Remove old backups, keep N most recent
- Automatic cleanup based on retention policy

### Restore functionality
- `/backup restore <path>` - Restore from backup file
- Safety checks before restore (confirm with user)
- Automatic backup before restore (backup-before-restore)
- Restore specific conversation by ID

### Advanced features
- Compression: `.db.gz` format for smaller backups
- Incremental backups: Only changed data since last backup
- Differential backups: Changed data since base backup
- Checksum verification: SHA256 for backup integrity
- Encrypted backups: Password-protected backup files
- Remote destinations: S3, SFTP, rsync, etc.
- Scheduled backups: Automatic periodic backups

### Progress improvements
- Show progress for all file sizes (with different thresholds)
- Estimated time remaining
- Transfer speed (MB/s)
- Colorized progress bar
- Sound/notification on completion

## Notes

### Database architecture context
- DuckDB uses Write-Ahead Log (WAL) for transactions
- WAL file (`memory.db.wal`) tracks uncommitted changes
- During backup, must ensure WAL is flushed via CHECKPOINT
- History#close already does CHECKPOINT before closing (history.rb:380)
- After backup, reopening database will replay any remaining WAL entries

### Worker coordination details
- Three workers: conversation-summarizer, exchange-summarizer, embeddings
- All inherit from PausableTask with cooperative pausing
- Workers use critical sections to protect database writes
- Application already waits for critical sections on shutdown (application.rb:44-47)
- Backup should follow similar pattern: pause, wait, checkpoint, close, copy

### File copy considerations
- FileUtils.cp is fast for small files (direct kernel copy)
- Manual chunked copy needed for progress bar on large files
- 8 KB read chunks balance memory usage and syscall overhead
- Progress updates every 100 KB balance feedback and performance
- Carriage return (\r) allows in-place progress updates

### Path handling
- Respect user's current working directory for relative paths
- Support `~` expansion for home directory (via File.expand_path)
- Validate paths stay within safe boundaries (no arbitrary file access)
- Consider symlink handling (resolve or preserve?)

### Testing challenges
- Time-dependent tests (timestamps) need time mocking
- File I/O tests need temp directories
- Progress bar tests need large files (or mocking)
- Worker tests need thread coordination
- Database tests need test database fixture

### Compatibility notes
- Ruby 3.4.7 with PRISM parser
- DuckDB v1.4.1 (native bindings)
- ANSI terminal required for progress bar (should degrade gracefully)
- Cross-platform considerations (Linux primary, macOS/Windows?)

## Example usage

```bash
# Default backup (current directory)
> /backup
Pausing background workers...
Closing database connections...
Backing up database...
[==========>] 100% (24.5 MB / 24.5 MB)
Verifying backup...
Reopening database...
Resuming background workers...

Backup created successfully:
  Path: ./memory-2025-10-30-143022.db
  Size: 24.5 MB
  Time: 2025-10-30 14:30:22

# Custom destination
> /backup ~/backups/important-backup.db
Pausing background workers...
Closing database connections...
Backing up database...
Verifying backup...
Reopening database...
Resuming background workers...

Backup created successfully:
  Path: /home/user/backups/important-backup.db
  Size: 2.1 MB
  Time: 2025-10-30 14:32:15

# Error handling example
> /backup /readonly/path/backup.db
Error: Destination directory is not writable

# Insufficient space example
> /backup /mnt/full-disk/backup.db
Error: Insufficient disk space (need 24.5 MB, have 10.2 MB)
```

## References

- GitHub Issue: https://github.com/mgreenly/nu-agent/issues/9
- Dependency Issue: https://github.com/mgreenly/nu-agent/issues/5 (completed)
- DuckDB Documentation: https://duckdb.org/docs/
- Ruby FileUtils: https://ruby-doc.org/stdlib-3.4.0/libdoc/fileutils/rdoc/FileUtils.html
