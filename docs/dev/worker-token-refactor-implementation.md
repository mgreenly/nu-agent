# WorkerToken Refactoring Implementation Guide

## Overview

This guide provides step-by-step implementation details for unifying the WorkerToken and PausableTask pause mechanisms.

## Current Architecture Analysis

### WorkerToken (Simple Counter)
- **Purpose**: Track active orchestrator threads
- **Location**: `lib/nu/agent/worker_token.rb:6-40`
- **Database**: Increments/decrements "active_workers" counter
- **Users**: InputProcessor creates one per exchange

### PausableTask (Pause/Resume System)
- **Purpose**: Allow background workers to be paused
- **Location**: `lib/nu/agent/pausable_task.rb:6-135`
- **Synchronization**: Mutex + ConditionVariable
- **Users**: ConversationSummarizer, ExchangeSummarizer, EmbeddingGenerator

## Detailed Implementation Steps

### Step 1: Create Enhanced WorkerToken

Create a new version that supports both counting and pausing:

```ruby
# lib/nu/agent/worker_token_v2.rb
module Nu
  module Agent
    class WorkerTokenV2
      attr_reader :type

      def initialize(history, type: :orchestrator, pausable: false, name: nil)
        @history = history
        @type = type
        @pausable = pausable
        @name = name || "#{type}_#{object_id}"
        @active = false
        @paused = false
        @mutex = Mutex.new
        @pause_cv = ConditionVariable.new
      end

      # === Counting Methods (All Types) ===

      def activate
        @mutex.synchronize do
          return if @active

          @history.increment_workers(@type)
          @active = true
          log_state_change("activated")
        end
      end

      def release
        @mutex.synchronize do
          return unless @active

          @history.decrement_workers(@type)
          @active = false
          log_state_change("released")
        end
      end

      def active?
        @mutex.synchronize { @active }
      end

      # === Pause Methods (Pausable Workers Only) ===

      def pause
        raise "Worker #{@name} is not pausable" unless @pausable

        @mutex.synchronize do
          return if @paused

          @paused = true
          log_state_change("paused")
        end
      end

      def resume
        raise "Worker #{@name} is not pausable" unless @pausable

        @mutex.synchronize do
          return unless @paused

          @paused = false
          @pause_cv.broadcast
          log_state_change("resumed")
        end
      end

      def check_pause(&shutdown_check)
        return unless @pausable

        @mutex.synchronize do
          while @paused
            # Check for shutdown if block given
            break if shutdown_check && shutdown_check.call

            # Wait with timeout to allow periodic shutdown checks
            @pause_cv.wait(@mutex, 0.1)
          end
        end
      end

      def paused?
        @mutex.synchronize { @paused }
      end

      def wait_until_paused(timeout: 5)
        return true unless @pausable
        return true if paused?

        deadline = Time.now + timeout

        loop do
          return true if paused?
          return false if Time.now > deadline
          sleep 0.05
        end
      end

      private

      def log_state_change(action)
        # Optional: Add logging for debugging
        # puts "[#{Time.now}] WorkerToken #{@name}: #{action}"
      end
    end
  end
end
```

### Step 2: Adapter for Existing PausableTask

Create an adapter to use new WorkerToken while keeping PausableTask interface:

```ruby
# lib/nu/agent/pausable_task_with_token.rb
module Nu
  module Agent
    class PausableTaskWithToken < PausableTask
      def initialize(history:, status_info:, shutdown_flag:, worker_name: nil)
        super(status_info: status_info, shutdown_flag: shutdown_flag)

        # Create a pausable WorkerToken for this background worker
        @worker_token = WorkerTokenV2.new(
          history,
          type: :background_worker,
          pausable: true,
          name: worker_name || self.class.name
        )

        @history = history
      end

      def start_worker
        Thread.new do
          Thread.current.report_on_exception = false
          Thread.current.name = @worker_token.name

          # Register this background worker
          @worker_token.activate

          begin
            run_worker_loop
          rescue StandardError => e
            handle_worker_error(e)
          ensure
            # Unregister when done
            @worker_token.release
          end
        end
      end

      def pause
        @worker_token.pause
        update_status(paused: true)
      end

      def resume
        @worker_token.resume
        update_status(paused: false)
      end

      def wait_until_paused(timeout: 5)
        @worker_token.wait_until_paused(timeout: timeout)
      end

      protected

      def check_pause
        @worker_token.check_pause { shutdown_requested? }
      end

      private

      def update_status(paused: nil, running: nil)
        @status_mutex.synchronize do
          @status["paused"] = paused unless paused.nil?
          @status["running"] = running unless running.nil?
        end
      end

      def handle_worker_error(error)
        # Log error, update status, etc.
        update_status(running: false)
        raise error
      end
    end
  end
end
```

### Step 3: Update WorkerCounter for Multiple Types

```ruby
# lib/nu/agent/worker_counter_v2.rb
module Nu
  module Agent
    class WorkerCounterV2
      WORKER_TYPES = [:orchestrator, :background_worker].freeze

      def initialize(db, mutex)
        @db = db
        @mutex = mutex
        ensure_metadata_keys
      end

      def increment_workers(type = :orchestrator)
        validate_type!(type)
        modify_counter(type, 1)
      end

      def decrement_workers(type = :orchestrator)
        validate_type!(type)
        modify_counter(type, -1)
      end

      def active_count(type = :orchestrator)
        validate_type!(type)
        key = counter_key(type)

        @mutex.synchronize do
          result = @db.execute("SELECT value FROM metadata WHERE key = ?", key).first
          result ? result[0] : 0
        end
      end

      def all_counts
        WORKER_TYPES.each_with_object({}) do |type, counts|
          counts[type] = active_count(type)
        end
      end

      def any_active?(type = nil)
        if type
          active_count(type) > 0
        else
          WORKER_TYPES.any? { |t| active_count(t) > 0 }
        end
      end

      def workers_idle?(type = nil)
        !any_active?(type)
      end

      def wait_for_idle(type: nil, timeout: 5)
        deadline = Time.now + timeout

        loop do
          return true if workers_idle?(type)
          return false if Time.now > deadline
          sleep 0.05
        end
      end

      private

      def validate_type!(type)
        unless WORKER_TYPES.include?(type)
          raise ArgumentError, "Invalid worker type: #{type}. Must be one of: #{WORKER_TYPES.join(', ')}"
        end
      end

      def counter_key(type)
        "active_#{type}_count"
      end

      def ensure_metadata_keys
        @mutex.synchronize do
          WORKER_TYPES.each do |type|
            key = counter_key(type)
            existing = @db.execute("SELECT 1 FROM metadata WHERE key = ?", key).first
            unless existing
              @db.execute("INSERT INTO metadata (key, value) VALUES (?, ?)", key, 0)
            end
          end
        end
      end

      def modify_counter(type, delta)
        key = counter_key(type)

        @mutex.synchronize do
          @db.execute("BEGIN TRANSACTION")
          begin
            current = @db.execute("SELECT value FROM metadata WHERE key = ?", key).first
            new_value = [(current ? current[0] : 0) + delta, 0].max
            @db.execute("UPDATE metadata SET value = ? WHERE key = ?", new_value, key)
            @db.execute("COMMIT")
            new_value
          rescue => e
            @db.execute("ROLLBACK")
            raise e
          end
        end
      end
    end
  end
end
```

### Step 4: Create Unified Coordination Manager

```ruby
# lib/nu/agent/work_coordinator.rb
module Nu
  module Agent
    class WorkCoordinator
      def initialize(history:, background_worker_manager:)
        @history = history
        @background_worker_manager = background_worker_manager
        @mutex = Mutex.new
      end

      # For /backup command
      def prepare_for_backup(timeout: 10)
        @mutex.synchronize do
          # 1. Pause all background workers
          pause_background_workers

          # 2. Wait for orchestrators to finish
          unless wait_for_orchestrators_idle(timeout: timeout / 2)
            resume_background_workers
            return false
          end

          # 3. Wait for background workers to reach pause state
          unless wait_for_workers_paused(timeout: timeout / 2)
            resume_background_workers
            return false
          end

          true
        end
      end

      # For external editor (future)
      def prepare_for_external_editor(timeout: 5)
        @mutex.synchronize do
          # Store current worker state
          @pre_editor_state = capture_worker_state

          # Pause everything
          pause_background_workers

          # Wait for safe state
          wait_for_orchestrators_idle(timeout: timeout)
        end
      end

      def restore_after_external_editor
        @mutex.synchronize do
          resume_background_workers if @pre_editor_state
          @pre_editor_state = nil
        end
      end

      def cleanup_after_backup
        @mutex.synchronize do
          resume_background_workers
        end
      end

      # Query methods
      def status
        {
          orchestrators: @history.active_count(:orchestrator),
          background_workers: @history.active_count(:background_worker),
          paused: background_workers_paused?
        }
      end

      private

      def pause_background_workers
        @background_worker_manager.pause_all
      end

      def resume_background_workers
        @background_worker_manager.resume_all
      end

      def wait_for_orchestrators_idle(timeout:)
        @history.wait_for_idle(type: :orchestrator, timeout: timeout)
      end

      def wait_for_workers_paused(timeout:)
        @background_worker_manager.wait_until_all_paused(timeout: timeout)
      end

      def background_workers_paused?
        @background_worker_manager.all_paused?
      end

      def capture_worker_state
        {
          timestamp: Time.now,
          orchestrators_active: @history.active_count(:orchestrator),
          workers_active: @history.active_count(:background_worker),
          workers_paused: background_workers_paused?
        }
      end
    end
  end
end
```

### Step 5: Update Existing Classes

#### Update InputProcessor to use new token type:

```ruby
# lib/nu/agent/input_processor.rb (partial)
def process_input(input)
  # Use the new WorkerTokenV2 with type specification
  worker_token = WorkerTokenV2.new(application.history, type: :orchestrator)
  worker_token.activate

  begin
    spawn_orchestrator(input)
  ensure
    worker_token.release
  end
end
```

#### Update BackupCommand to use coordinator:

```ruby
# lib/nu/agent/commands/backup_command.rb (partial)
def execute(args = [])
  coordinator = WorkCoordinator.new(
    history: @history,
    background_worker_manager: @background_worker_manager
  )

  unless coordinator.prepare_for_backup(timeout: 10)
    output.puts "Could not achieve safe state for backup"
    return
  end

  begin
    backup_database
  ensure
    coordinator.cleanup_after_backup
  end
end
```

#### Update background workers to inherit from new base:

```ruby
# lib/nu/agent/conversation_summarizer.rb (partial)
class ConversationSummarizer < PausableTaskWithToken
  def initialize(history:, status_info:, shutdown_flag:)
    super(
      history: history,
      status_info: status_info,
      shutdown_flag: shutdown_flag,
      worker_name: "conversation_summarizer"
    )
  end

  protected

  def do_work
    # Existing summarization logic
  end
end
```

## Testing Strategy

### Unit Tests

```ruby
# spec/nu/agent/worker_token_v2_spec.rb
RSpec.describe Nu::Agent::WorkerTokenV2 do
  describe "orchestrator tokens" do
    it "counts active orchestrators" do
      token = WorkerTokenV2.new(history, type: :orchestrator)
      token.activate
      expect(history.active_count(:orchestrator)).to eq(1)
      token.release
      expect(history.active_count(:orchestrator)).to eq(0)
    end

    it "cannot be paused" do
      token = WorkerTokenV2.new(history, type: :orchestrator, pausable: false)
      expect { token.pause }.to raise_error(/not pausable/)
    end
  end

  describe "background worker tokens" do
    it "can be paused and resumed" do
      token = WorkerTokenV2.new(history, type: :background_worker, pausable: true)
      token.pause
      expect(token.paused?).to be true
      token.resume
      expect(token.paused?).to be false
    end

    it "blocks on check_pause when paused" do
      token = WorkerTokenV2.new(history, type: :background_worker, pausable: true)
      token.pause

      blocked = true
      thread = Thread.new do
        token.check_pause { false }
        blocked = false
      end

      sleep 0.1
      expect(blocked).to be true

      token.resume
      thread.join(1)
      expect(blocked).to be false
    end
  end
end
```

### Integration Tests

```ruby
# spec/integration/work_coordination_spec.rb
RSpec.describe "Work Coordination" do
  it "coordinates backup with active orchestrators" do
    # Start an orchestrator
    orchestrator_token = WorkerTokenV2.new(history, type: :orchestrator)
    orchestrator_token.activate

    # Start background workers
    background_worker_manager.start_all

    # Try to prepare for backup
    coordinator = WorkCoordinator.new(
      history: history,
      background_worker_manager: background_worker_manager
    )

    # Should wait for orchestrator
    result = coordinator.prepare_for_backup(timeout: 0.5)
    expect(result).to be false

    # Release orchestrator
    orchestrator_token.release

    # Now should succeed
    result = coordinator.prepare_for_backup(timeout: 1)
    expect(result).to be true
  end
end
```

## Migration Checklist

- [ ] Create WorkerTokenV2 class
- [ ] Create PausableTaskWithToken adapter
- [ ] Update WorkerCounter to handle types
- [ ] Create WorkCoordinator
- [ ] Add comprehensive tests
- [ ] Update InputProcessor
- [ ] Update BackupCommand
- [ ] Update all background workers
- [ ] Run full test suite
- [ ] Test with real /backup command
- [ ] Test with mock external editor
- [ ] Update documentation
- [ ] Consider deprecation path for old classes

## Rollback Plan

If issues arise:

1. Keep old classes in place (PausableTask, original WorkerToken)
2. Use feature flag to switch between implementations
3. Gradually migrate one component at a time
4. Can run both systems in parallel during transition

## Performance Considerations

- WorkerTokenV2 adds minimal overhead (one extra field check)
- Database operations remain the same complexity
- Mutex contention is actually reduced (single mutex vs dual)
- Polling intervals can be tuned (currently 50ms)

## Future Extensions

This architecture enables:

1. **Priority Levels**: High-priority work can preempt low-priority
2. **Resource Limits**: Max orchestrators, max workers
3. **Work Queuing**: Queue work when at capacity
4. **Monitoring**: Real-time worker activity dashboard
5. **Graceful Degradation**: Automatic pause when system overloaded