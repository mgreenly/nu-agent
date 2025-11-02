# Pause Mechanisms - Quick Reference

## At a Glance

Three distinct pause/coordination systems. DO NOT unify them.

```
WorkerToken          PausableTask         ConsoleIO
(counting)           (pause control)      (state mgmt)
    |                    |                    |
    v                    v                    v
Orchestrators       Background Workers    User Input/Output
(short-lived)       (long-lived)          (event-driven)
```

## WorkerToken / WorkerCounter

**Purpose**: Count active orchestrator threads for future editor feature

**Location**: 
- `lib/nu/agent/worker_token.rb`
- `lib/nu/agent/worker_counter.rb`
- Used in `lib/nu/agent/input_processor.rb`

**API**:
```ruby
token = WorkerToken.new(history)
token.activate          # Increment active workers
token.active?           # Check if active
token.release           # Decrement active workers
```

**Characteristics**:
- Idempotent activate/release
- Persists count to database (via WorkerCounter)
- Per-exchange lifecycle
- No pause capability

**When to use**: Track orchestrator thread lifecycle for future features

---

## PausableTask

**Purpose**: Safely pause and resume background workers

**Location**: 
- `lib/nu/agent/pausable_task.rb`
- Inherited by: ConversationSummarizer, ExchangeSummarizer, EmbeddingGenerator
- Managed by: `lib/nu/agent/background_worker_manager.rb`

**API**:
```ruby
worker.pause                          # Request pause
worker.resume                         # Resume work
worker.wait_until_paused(timeout: 5) # Wait for pause confirmation
worker.paused?                        # Check pause state (via status)
```

**Synchronization**:
- `@pause_mutex` - Protects pause state
- `@pause_cv` - Condition variable for pause waits
- `@status_mutex` - Shared with application, tracks running/paused/metrics

**Characteristics**:
- Cooperative pausing (checks at safe points)
- Timeout-aware
- Tracks running/paused/metrics status
- Respects shutdown signals

**When to use**: Control long-lived background workers (especially during critical operations like backup)

---

## ConsoleIO State Machine

**Purpose**: Manage console I/O state transitions

**Location**: 
- `lib/nu/agent/console_io.rb`
- `lib/nu/agent/console_io_states.rb`

**API**:
```ruby
console.pause                     # Pause current state
console.resume                    # Resume from paused state
console.current_state_name        # Check state
```

**States**:
- `IdleState` - Ready for input
- `ReadingUserInputState` - Reading from user
- `StreamingAssistantState` - Showing spinner
- `ProgressState` - Showing progress
- `PausedState` - Paused (saves previous state)

**Characteristics**:
- State-based transitions
- Saves/restores previous state
- No threading concerns
- Single-threaded state management

**When to use**: Manage user I/O responsiveness

---

## Usage Patterns

### BackupCommand: PausableTask in Action

```ruby
# 1. Request pause
app.worker_manager.pause_all

# 2. Wait for confirmation (with timeout)
app.worker_manager.wait_until_all_paused(timeout: 5.0)

# 3. Safe to access database now
app.history.close
# ... backup file ...
app.reopen_database

# 4. Resume (always, even if backup failed)
app.worker_manager.resume_all  # [in ensure block]
```

### InputProcessor: WorkerToken Usage

```ruby
# 1. Create token
worker_token = WorkerToken.new(application.history)

# 2. Activate (increment counter)
worker_token.activate

# 3. Spawn orchestrator thread
thread = spawn_orchestrator_thread(input, worker_token)

# 4. Release (decrement counter) in ensure block
worker_token.release
```

### ConsoleIO: State Pausing

```ruby
# Pause from any state (saves previous state)
console.pause

# Resume to previous state
console.resume  # Only valid from PausedState
```

---

## Common Mistakes to Avoid

### ❌ DON'T try to pause orchestrators
Orchestrators are short-lived and fire-and-forget. They're counted (WorkerToken) but never paused.

### ❌ DON'T use WorkerToken for background workers
WorkerToken only counts. PausableTask provides pause/resume/wait.

### ❌ DON'T forget to resume workers
Always use ensure blocks:
```ruby
app.worker_manager.pause_all
begin
  # critical operation
ensure
  app.worker_manager.resume_all
end
```

### ❌ DON'T call resume from non-PausedState
ConsoleIO.resume only works when already paused:
```ruby
console.pause    # OK
console.resume   # OK - transitions back

console.resume   # ERROR - not in PausedState
```

---

## Threading Model Quick Facts

| Aspect | Orchestrators | Workers | ConsoleIO |
|--------|---------------|---------|-----------|
| **Created by** | InputProcessor | BackgroundWorkerManager | Application init |
| **Lifetime** | Per input (short) | Session (long) | Session |
| **Count** | WorkerToken | PausableTask | N/A |
| **Pausable?** | NO | YES | YES (state) |
| **Mutex** | Lightweight | Dual (pause + status) | None (state pattern) |

---

## Synchronization Reference

### WorkerToken: Simple Counting
```ruby
@mutex.synchronize do
  @history.increment_workers if not @active
  @active = true
end
```

### PausableTask: Pause Coordination
```ruby
@pause_mutex.synchronize do
  @paused = true
  @status_mutex.synchronize { @status["paused"] = true }
  @pause_cv.broadcast
end
```

### ConsoleIO: State Transitions
```ruby
@state.on_exit
@previous_state = @state
@state = new_state
@state.on_enter
```

---

## Design Principles

1. **Single Responsibility**: Each class solves one problem
2. **Appropriate Synchronization**: Match synchronization to workload
3. **Idempotency**: Safe to call methods multiple times
4. **Graceful Degradation**: Cooperative, not forced
5. **Clear Semantics**: Method names indicate behavior

---

## Performance Considerations

### WorkerToken
- Minimal overhead (just increment/decrement)
- Persists to database (acceptable for per-exchange operations)
- No locks during normal execution

### PausableTask
- Checks pause state at safe points (200ms intervals)
- Dual mutexes (safe, but could be consolidated)
- wait_until_paused uses polling (acceptable, timeout-aware)

### ConsoleIO
- No threading overhead
- State pattern is efficient

---

## Testing Tips

### WorkerToken
```ruby
token = WorkerToken.new(history)
token.activate
expect(history).to have_received(:increment_workers).once
token.release
expect(history).to have_received(:decrement_workers).once
```

### PausableTask
```ruby
worker = ConversationSummarizer.new(...)
worker.pause
expect(worker.wait_until_paused(timeout: 1)).to be true
worker.resume
```

### ConsoleIO
```ruby
console.pause
expect(console.current_state_name).to eq(:paused)
console.resume
expect(console.current_state_name).not_to eq(:paused)
```

---

## When to Add New Pause Mechanisms

**Don't.** Before adding a new pause system:

1. ✅ Check if PausableTask works for your case
2. ✅ Check if WorkerToken is sufficient
3. ✅ Check if ConsoleIO state management applies

Only create new pause mechanisms if:
- None of above fit your requirements
- You've got clear use case and design
- You've documented the synchronization model
- You've added comprehensive tests

---

## References

- `pause-mechanism-analysis.md` - Comprehensive technical analysis
- `pause-mechanisms-diagram.txt` - Visual architecture
- Source: `lib/nu/agent/pausable_task.rb`
- Source: `lib/nu/agent/worker_token.rb`
- Source: `lib/nu/agent/background_worker_manager.rb`
