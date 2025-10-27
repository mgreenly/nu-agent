# DuckDB Database Safety Guide

## Overview

This document covers how to safely use DuckDB, prevent corruption, and recover from issues.

## How DuckDB Works

### Write-Ahead Logging (WAL)

DuckDB uses a **Write-Ahead Log (WAL)** for durability and crash recovery:

1. **On Transaction Commit**: Changes are written to the `.wal` file BEFORE being applied to the main `.db` file
2. **On Recovery**: If the database crashes, DuckDB automatically replays the WAL on next startup
3. **Checkpointing**: Periodically, WAL entries are applied to the main database file and the WAL is truncated

**You will see a `.wal` file during normal operation** - this is expected and healthy!

### The Checkpoint Process

**Automatic checkpointing** happens:
- When WAL reaches 16MB (configurable via `checkpoint_threshold`)
- **On clean database shutdown** (via `db.close()`)

**Manual checkpointing**:
```sql
CHECKPOINT;           -- Fails if transactions are running
FORCE CHECKPOINT;     -- Aborts transactions and checkpoints
```

### Durability Guarantees

DuckDB explicitly calls `fsync()` to force WAL writes to persistent storage, bypassing OS caches. This ensures committed transactions survive:
- Process crashes
- Power failures
- OS crashes

## What Causes Corruption

### 1. Abrupt Termination During Write (Most Common)

**Symptoms:**
- Database file left in inconsistent state
- `.wal` file remains after crash
- Error: "Corrupt WAL file: checksum mismatch"

**Causes:**
- `kill -9` (SIGKILL) - immediate termination, no cleanup
- Out of Memory (OOM) kills
- Power loss (rare with `fsync()`)
- Disk I/O errors during write

### 2. Disk Space Exhaustion

**Symptoms:**
- Write operations fail
- Partial transactions written
- Database in inconsistent state

**Prevention:**
- Monitor available disk space
- Set up alerts when space < 10%

### 3. Multiple Writers Without Proper Locking

**Symptoms:**
- Corruption from concurrent writes
- "Database is locked" errors

**Prevention:**
- DuckDB handles this automatically with WAL mode
- Our application uses a single History instance with thread-safe connections

### 4. File System Issues

**Causes:**
- Network-attached storage (NFS, etc.) with inconsistent behavior
- Bad disk sectors
- File system corruption

## Current Implementation Analysis

### ✅ What We're Doing Right

1. **Clean shutdown handling** (`application.rb:50`):
   ```ruby
   ensure
     @shutdown = true
     @tui&.close
     # Wait for critical sections to complete
     sleep 0.1 while in_critical_section? && (Time.now - start_time) < timeout
     active_threads.each(&:join)
     history&.close  # Triggers automatic checkpoint
   end
   ```

2. **Thread-safe connection pooling** (`history.rb:28-38`):
   - One connection per thread
   - Mutex-protected connection management
   - Prevents concurrent write conflicts

3. **No signal trapping for SIGINT**:
   - Allows Ruby's Interrupt exception to propagate
   - Ensures `ensure` blocks run for cleanup

### ⚠️ Potential Issues

1. **No explicit CHECKPOINT before close**
   - We rely on automatic checkpoint during `db.close()`
   - If close is interrupted, WAL may not flush

2. **No WAL file detection on startup**
   - Leftover `.wal` files indicate previous unclean shutdown
   - We don't currently check for or log this

3. **No disk space checks**
   - Write operations can fail silently if disk is full

4. **SIGKILL (kill -9) will corrupt**
   - No way to prevent this - it's immediate termination
   - Can only detect and recover afterward

## Recommended Improvements

### 1. Explicit Checkpoint Before Shutdown

Add explicit checkpoint to `History#close`:

```ruby
def close
  @connection_mutex.synchronize do
    # Explicitly checkpoint before closing
    begin
      connection.query("CHECKPOINT")
    rescue StandardError => e
      # Log but don't fail - close will checkpoint anyway
      warn "Checkpoint failed during shutdown: #{e.message}"
    end

    @connections.each_value(&:close)
    @connections.clear
  end
  @db.close
end
```

**Benefit**: Ensures WAL is flushed even if `db.close()` is interrupted.

### 2. WAL File Detection on Startup

Add check in `History#initialize`:

```ruby
def initialize(db_path: ENV["NUAGENT_DATABASE"] || ...)
  @db_path = db_path
  ensure_db_directory(db_path)

  # Check for leftover WAL file (indicates unclean shutdown)
  wal_path = "#{db_path}.wal"
  if File.exist?(wal_path)
    warn "⚠️  WAL file detected: Previous shutdown may have been unclean"
    warn "   Database will automatically recover on connect..."
  end

  @db = DuckDB::Database.open(db_path)
  # ... rest of initialization

  # If WAL was present, it's now recovered - log success
  if File.exist?(wal_path)
    warn "✅ Database recovery completed successfully"
  end
end
```

**Benefit**:
- Alerts you to unclean shutdowns
- Confirms successful recovery
- Helps diagnose corruption patterns

### 3. Disk Space Monitoring

Add periodic check (in background worker or on critical operations):

```ruby
def check_disk_space
  stat = Sys::Filesystem.stat(@db_path)
  available_mb = stat.bytes_available / 1024 / 1024
  total_mb = stat.bytes_total / 1024 / 1024
  percent_free = (available_mb.to_f / total_mb * 100).round(1)

  if percent_free < 10
    warn "⚠️  Low disk space: #{available_mb}MB available (#{percent_free}%)"
  end
end
```

**Requires**: `sys-filesystem` gem

### 4. Corruption Recovery Procedure

Document recovery steps:

```bash
# 1. Check if WAL file exists
ls -lh db/memory.db*

# 2. If .wal exists, try automatic recovery
#    Just open the database - DuckDB will replay WAL automatically
ruby -e "require 'duckdb'; db = DuckDB::Database.open('db/memory.db'); db.close"

# 3. If corruption persists, restore from backup
cp db/memory-rollback.db db/memory.db

# 4. If no backup, try salvaging with DuckDB recovery mode
# (Future: investigate DuckDB recovery options)
```

## Best Practices

### ✅ DO

1. **Always close database connections properly**
   - Use `ensure` blocks
   - Call `history.close` on shutdown

2. **Let automatic checkpointing work**
   - Don't disable `checkpoint_on_shutdown`
   - Don't set `checkpoint_threshold` too high

3. **Use transactions for related writes**
   ```ruby
   history.transaction do
     history.add_message(...)
     history.update_exchange(...)
   end
   ```

4. **Monitor disk space**
   - Keep at least 10% free
   - Alert when space is low

5. **Make regular backups**
   ```bash
   # Copy both files to be safe
   cp db/memory.db db/backups/memory-$(date +%Y%m%d).db
   cp db/memory.db.wal db/backups/memory-$(date +%Y%m%d).db.wal 2>/dev/null || true
   ```

6. **Test recovery procedures**
   - Periodically test backup restoration
   - Verify WAL replay works

### ❌ DON'T

1. **Don't use `kill -9` to stop the application**
   - Use `Ctrl-C` or `SIGTERM` instead
   - Gives cleanup handlers time to run

2. **Don't manually delete `.wal` files**
   - They contain uncommitted transactions
   - Let DuckDB manage them

3. **Don't run multiple instances on same database**
   - DuckDB handles this, but adds overhead
   - Better to use single instance with threading

4. **Don't ignore disk space warnings**
   - Write failures can corrupt database
   - Monitor proactively

5. **Don't write to database in signal handlers**
   - Signal handlers should set flags only
   - Let main thread do cleanup

## Recovery Procedures

### Scenario 1: Application Crashed, WAL File Remains

**Symptoms:**
- `db/memory.db.wal` file present after crash
- Application won't start or shows errors

**Recovery:**
```bash
# DuckDB will automatically recover on next start
# Just restart the application
bin/nu-agent

# If successful, the .wal file will be removed or truncated
```

### Scenario 2: "Corrupt WAL file" Error

**Symptoms:**
- Error: "Corrupt WAL file: checksum mismatch"
- Database won't open

**Recovery:**
```bash
# 1. Try automatic recovery (may fail)
ruby -e "require 'duckdb'; db = DuckDB::Database.open('db/memory.db'); db.close"

# 2. If that fails, restore from backup
cp db/memory-rollback.db db/memory.db
rm -f db/memory.db.wal  # Remove corrupt WAL

# 3. Restart application
bin/nu-agent
```

### Scenario 3: Out of Disk Space

**Symptoms:**
- Write operations failing
- "No space left on device" errors
- Database possibly corrupted

**Recovery:**
```bash
# 1. Free up disk space immediately
df -h  # Check disk usage
# Remove temporary files, old logs, etc.

# 2. Check database integrity
ruby -e "require 'duckdb'; db = DuckDB::Database.open('db/memory.db'); \
         conn = db.connect; \
         conn.query('PRAGMA integrity_check'); \
         db.close"

# 3. If corrupted, restore from backup
cp db/memory-rollback.db db/memory.db
```

### Scenario 4: Database File Locked

**Symptoms:**
- "Database is locked" error
- Can't open database

**Causes:**
- Another process has database open
- Stale lock from crash (rare with DuckDB)

**Recovery:**
```bash
# 1. Check for other processes
lsof db/memory.db
ps aux | grep nu-agent

# 2. Kill stale processes if found
kill <pid>

# 3. If no processes found, check for .wal file
ls -l db/memory.db*

# 4. Try reopening (DuckDB should recover)
bin/nu-agent
```

## Monitoring Checklist

Daily:
- [ ] Check application logs for "Checkpoint failed" warnings
- [ ] Verify no `.wal` files persist after clean shutdown

Weekly:
- [ ] Check disk space (`df -h`)
- [ ] Review database file size growth
- [ ] Test backup restoration

Monthly:
- [ ] Review corruption incidents
- [ ] Update backup retention policy
- [ ] Test recovery procedures

## Configuration Options

Available DuckDB pragmas for tuning:

```sql
-- Increase checkpoint threshold (default: 16MB)
PRAGMA checkpoint_threshold='32MB';

-- Disable automatic checkpoint (NOT RECOMMENDED)
PRAGMA disable_checkpoint_on_shutdown;

-- Check configuration
PRAGMA checkpoint_threshold;
```

**Recommendation**: Use defaults unless you have specific performance needs.

## Additional Resources

- [DuckDB WAL Documentation](https://duckdb.org/2024/10/30/analytics-optimized-concurrent-transactions)
- [DuckDB CHECKPOINT Statement](https://duckdb.org/docs/stable/sql/statements/checkpoint)
- [DuckDB Crash Recovery](https://duckdb.org/docs/stable/guides/troubleshooting/crashes)

## Summary

**Key Takeaways:**

1. **WAL files are normal** - don't panic when you see them
2. **Clean shutdown is critical** - always close database properly
3. **Automatic recovery works** - DuckDB replays WAL on startup
4. **Explicit checkpointing adds safety** - do it before close
5. **Monitor disk space** - corruption risk increases when full
6. **Regular backups** - your last line of defense
7. **Never use `kill -9`** - use `Ctrl-C` or `SIGTERM` instead

**The two times corruption happened:**
- Likely caused by unclean shutdown (OOM, `kill -9`, or crash during write)
- WAL file left behind is the indicator
- Implementing the recommended improvements will reduce risk
