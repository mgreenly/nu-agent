# WorkerToken Refactoring Proposal

## Executive Summary

Unify the pause mechanisms used by `/backup` command and the future external editor feature by extending WorkerToken to support both counting active exchanges AND pausing background workers.

## Current State

We have two separate coordination mechanisms:

1. **WorkerToken**: Counts active orchestrator threads (for future external editor)
2. **PausableTask**: Pauses background workers (for /backup command)

Both solve the same problem: **"When is it safe to do something disruptive?"**

## Proposed Refactoring

### Option 1: Extended WorkerToken (Recommended)

Transform WorkerToken into a comprehensive work coordination system that handles both orchestrator tracking and background worker pausing.

```ruby
# lib/nu/agent/worker_token.rb
module Nu
  module Agent
    class WorkerToken
      def initialize(history, type: :orchestrator, pausable: false)
        @history = history
        @type = type  # :orchestrator or :background_worker
        @pausable = pausable
        @active = false
        @paused = false
        @mutex = Mutex.new
        @pause_cv = ConditionVariable.new
      end

      # Existing methods for orchestrators
      def activate
        @mutex.synchronize do
          return if @active
          @history.increment_workers(@type)
          @active = true
        end
      end

      def release
        @mutex.synchronize do
          return unless @active
          @history.decrement_workers(@type)
          @active = false
        end
      end

      # New methods for pausable workers
      def pause
        return unless @pausable
        @mutex.synchronize do
          @paused = true
        end
      end

      def resume
        return unless @pausable
        @mutex.synchronize do
          @paused = false
          @pause_cv.broadcast
        end
      end

      def check_pause
        return unless @pausable
        @mutex.synchronize do
          while @paused
            @pause_cv.wait(@mutex)
          end
        end
      end

      def paused?
        @mutex.synchronize { @paused }
      end
    end
  end
end
```

### Modified PausableTask

Background workers would now use WorkerToken for pause coordination:

```ruby
# lib/nu/agent/pausable_task.rb
module Nu
  module Agent
    class PausableTask
      def initialize(history:, status_info:, shutdown_flag:)
        @status = status_info[:status]
        @status_mutex = status_info[:mutex]
        @shutdown_flag = shutdown_flag

        # Use WorkerToken for pause management
        @worker_token = WorkerToken.new(
          history,
          type: :background_worker,
          pausable: true
        )
      end

      def start_worker
        Thread.new do
          Thread.current.report_on_exception = false
          @worker_token.activate  # Register as active worker
          run_worker_loop
        rescue StandardError
          @status_mutex.synchronize do
            @status["running"] = false
          end
        ensure
          @worker_token.release  # Unregister when done
        end
      end

      def pause
        @worker_token.pause
        @status_mutex.synchronize do
          @status["paused"] = true
        end
      end

      def resume
        @worker_token.resume
        @status_mutex.synchronize do
          @status["paused"] = false
        end
      end

      protected

      def check_pause
        @worker_token.check_pause
      end

      # Rest remains similar...
    end
  end
end
```

### Unified WorkerCounter

Track both types of workers in the database:

```ruby
# lib/nu/agent/worker_counter.rb
module Nu
  module Agent
    class WorkerCounter
      def increment(type = :orchestrator)
        key = "active_#{type}_count"
        @mutex.synchronize do
          count = @db.execute("SELECT value FROM metadata WHERE key = ?", key).first
          if count
            @db.execute("UPDATE metadata SET value = ? WHERE key = ?", count[0] + 1, key)
          else
            @db.execute("INSERT INTO metadata (key, value) VALUES (?, ?)", key, 1)
          end
        end
      end

      def decrement(type = :orchestrator)
        key = "active_#{type}_count"
        @mutex.synchronize do
          count = @db.execute("SELECT value FROM metadata WHERE key = ?", key).first
          if count && count[0] > 0
            @db.execute("UPDATE metadata SET value = ? WHERE key = ?", count[0] - 1, key)
          end
        end
      end

      def active_count(type = :orchestrator)
        key = "active_#{type}_count"
        @mutex.synchronize do
          result = @db.execute("SELECT value FROM metadata WHERE key = ?", key).first
          result ? result[0] : 0
        end
      end

      def any_active?
        active_count(:orchestrator) > 0 || active_count(:background_worker) > 0
      end

      def wait_for_idle(timeout: 5)
        deadline = Time.now + timeout
        loop do
          return true unless any_active?
          return false if Time.now > deadline
          sleep 0.1
        end
      end
    end
  end
end
```

### Simplified BackgroundWorkerManager

Can now leverage the unified system:

```ruby
# lib/nu/agent/background_worker_manager.rb
module Nu
  module Agent
    class BackgroundWorkerManager
      def pause_all
        workers.each(&:pause)
      end

      def resume_all
        workers.each(&:resume)
      end

      def wait_until_all_paused(timeout: 5)
        deadline = Time.now + timeout
        workers.all? do |worker|
          remaining = deadline - Time.now
          return false if remaining <= 0
          worker.wait_until_paused(timeout: remaining)
        end
      end

      # New unified method for external editor/backup
      def wait_for_safe_state(timeout: 10)
        # Wait for both orchestrators and background workers
        @history.wait_for_idle(timeout: timeout)
      end
    end
  end
end
```

### Usage Examples

#### For /backup command:
```ruby
def execute(args = [])
  # Pause all background workers
  @background_worker_manager.pause_all

  # Wait for orchestrators to finish and workers to pause
  @background_worker_manager.wait_for_safe_state(timeout: 10)

  backup_database

  @background_worker_manager.resume_all
end
```

#### For external editor (future):
```ruby
def launch_external_editor
  # Pause all background workers to prevent output
  @background_worker_manager.pause_all

  # Wait for safe state
  @background_worker_manager.wait_for_safe_state(timeout: 5)

  # Launch editor
  system("vim", temp_file)

  # Resume workers
  @background_worker_manager.resume_all
end
```

## Benefits of This Refactoring

1. **Unified Coordination**: Single mechanism for all work coordination
2. **Database Visibility**: Can query both orchestrator and worker counts
3. **Simpler Mental Model**: One concept (WorkerToken) instead of two
4. **Future-Proof**: Easy to add new worker types or pause behaviors
5. **Backward Compatible**: Existing code continues to work with minimal changes

## Migration Path

1. **Phase 1**: Extend WorkerToken with pausable flag and methods
2. **Phase 2**: Update PausableTask to use WorkerToken internally
3. **Phase 3**: Modify WorkerCounter to track types
4. **Phase 4**: Update BackgroundWorkerManager with unified methods
5. **Phase 5**: Test with both /backup and future external editor

## Alternative: Keep Systems Separate

If you prefer to keep the systems separate (which is also valid), you could instead:

1. Keep WorkerToken for orchestrator counting only
2. Keep PausableTask for background worker pausing only
3. Add a new `CoordinationManager` that knows about both:

```ruby
class CoordinationManager
  def wait_for_safe_state(timeout: 10)
    # Wait for orchestrators to finish
    wait_for_orchestrators_idle(timeout: timeout/2)

    # Then pause and wait for background workers
    @background_worker_manager.pause_all
    @background_worker_manager.wait_until_all_paused(timeout: timeout/2)
  end

  def resume_all
    @background_worker_manager.resume_all
  end
end
```

This keeps the concerns separate but provides a unified interface for commands that need both.

## Recommendation

I recommend **Option 1 (Extended WorkerToken)** because:

1. Both mechanisms solve the same core problem
2. The unified counter in the database provides better observability
3. It reduces code duplication
4. It makes the system easier to understand (one concept vs two)

However, if you value separation of concerns more highly, the Alternative approach is also perfectly valid and might be easier to implement incrementally.

## Next Steps

1. Discuss which approach aligns better with your architecture goals
2. Create tests for the new unified behavior
3. Implement in phases to minimize risk
4. Test with both /backup and a mock external editor scenario