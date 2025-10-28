# Nu-Agent v0.11 Refactoring Plan

**Last Updated**: 2025-10-27
**Current Version**: 0.9.0
**Plan Status**: Ready to execute
**Prerequisites**: Recent refactorings completed (see below)

## Overview

Version 0.11 continues the architectural improvements from recent development work to address remaining technical debt and prepare the codebase for future feature development. This refactoring aims to reduce complexity, improve maintainability, and apply missing architectural patterns identified in the architecture analysis.

**Key Achievement from Recent Work**: Application class reduced from 500+ lines to 287 lines (43% reduction), with zero RuboCop violations achieved through systematic refactoring. Version will be bumped to 0.11.0 upon completion of this plan.

## What Was Completed Recently (Current: v0.9.0)

### ✅ Partial Goal 1: Break Up Application God Object

**Completed Extractions**:
- ✅ **ChatLoopOrchestrator** (264 lines) - Complete chat loop logic with context building
  - Moved from: application.rb
  - Manages exchange lifecycle, LLM requests, context document building, RAG pipeline
- ✅ **InputProcessor** (128 lines) - Input routing and thread management
  - Moved from: application.rb
  - Handles command routing, exchange tracking, thread coordination, interrupt handling
- ✅ **BackgroundWorkerManager** - Background worker coordination
  - Manages: summarization and man page indexer workers
  - Tracks: active threads, worker status
- ✅ **SessionStatistics** - Metrics tracking and reporting
  - Extracted from: formatter.rb
  - Handles: session metrics, statistics display, cost tracking
- ✅ **WorkerToken** - Safe worker lifecycle management
  - New pattern: prevents double-increment/decrement bugs
  - Thread-safe activation/release with idempotent operations
- ✅ **SpinnerState** - Spinner state encapsulation
  - Extracted state management from ConsoleIO
  - Value object pattern for spinner state tracking
- ✅ **Formatter Decomposition** - Split into specialized sub-formatters
  - ToolCallFormatter, ToolResultFormatter, LlmRequestFormatter
  - Better SRP adherence in formatters subdirectory

**Result**: Application class reduced from 500+ lines → 287 lines (43% reduction)

**Remaining Work for Goal 1**:
- ❌ SystemLifecycle - Startup, shutdown, signal handling still in Application
- ❌ ConversationCoordinator - High-level conversation flow coordination
- Application.rb still has 287 lines with multiple responsibilities

### ✅ Additional Recent Improvements

**Code Quality**:
- ✅ **RuboCop Violations Eliminated** - Achieved zero violations through systematic refactoring
- ✅ **Comprehensive Test Coverage** - Maintained high test coverage through all refactorings

**Thread Safety & Database**:
- ✅ **Database Foreign Key Constraints** - Added database-level integrity constraints
- ✅ **WorkerToken Pattern** - Prevents worker lifecycle bugs with thread-safe token management
- ✅ **Improved Ctrl-C Handling** - Better interrupt handling for improved UX

**Documentation**:
- ✅ **DuckDB Safety Documentation** - Comprehensive safety guide added
- ✅ **Architecture Analysis Updated** - Reflects all v0.10 changes (updated 2025-10-27)

### ❌ Goals 2-5: Not Started
- Goal 2: Event-Based Message Display (replace polling)
- Goal 3: State Pattern in ConsoleIO
- Goal 4: Chain of Responsibility for RAG Pipeline
- Goal 5: Decorator Pattern for Tools

## Required Reading

Before starting work on this plan, read these documents in order:

1. **docs/architecture-analysis.md** - Comprehensive analysis of architecture patterns (✓ Updated 2025-10-27)
2. **docs/design.md** - Database schema documentation
3. **lib/nu/agent/application.rb** - The main Application class (287 lines)
4. **lib/nu/agent/console_io.rb** - Console I/O with state management issues (626 lines)
5. **lib/nu/agent/formatter.rb** - Message display with polling issues (339 lines)
6. **lib/nu/agent/chat_loop_orchestrator.rb** - Orchestration patterns (264 lines)
7. **lib/nu/agent/input_processor.rb** - Input processing and thread coordination (128 lines)
8. **lib/nu/agent/background_worker_manager.rb** - Background worker management
9. **lib/nu/agent/history.rb** - Database facade and transaction management
10. **README.md** - Project overview and features

## Updated Code Locations

This section provides line number references to help you locate specific areas that need refactoring:

### Application Class (application.rb) - 287 lines
- **Initialization responsibilities**: Lines 22-29 (initialize method)
  - State initialization: `initialize_state` (line 88)
  - Configuration loading: `load_and_apply_configuration` (line 101)
  - Console system setup: `initialize_console_system` (line 113)
  - Status tracking: `initialize_status_tracking` (line 127)
  - Command registration: `initialize_commands` (line 138)
  - Background workers: `start_background_workers` (line 144)
- **REPL loop**: Lines 185-207
- **Critical section tracking**: Lines 167-183
  - `enter_critical_section` (line 167)
  - `exit_critical_section` (line 173)
  - `in_critical_section?` (line 179)
- **Thread coordination**: Delegates to BackgroundWorkerManager (lines 10-20)
- **Command routing**: Delegates to InputProcessor (line 53)
- **Signal handling**: Line 261 (`setup_signal_handlers`)
- **Shutdown sequence**: Lines 36-50 (in ensure block of run method)

### ConsoleIO State Management (console_io.rb)
- **State tracking**: `@mode` variable (`:input` or `:spinner`)
- **Spinner state**: SpinnerState encapsulation
- **State transitions**:
  - Input mode → Spinner mode: `show_spinner`
  - Spinner mode → Input mode: `hide_spinner`, `readline`

### Formatter Polling (formatter.rb) - 339 lines
- **Polling loop**: `wait_for_completion` method
- **Message fetching**: `display_new_messages` method
- **Message display**: `display_message` method

### ChatLoopOrchestrator RAG Pipeline (chat_loop_orchestrator.rb) - 264 lines
- **Context document building**: `build_context_document` method
- **RAG content assembly**: `build_rag_content` method
  - Redacted ranges
  - Spell checking
- **Request preparation**: `prepare_llm_request` method

## v0.11 Goals

---

### Goal 1: Complete Application Class Refactoring

**Priority**: HIGH

**Current State**:
- Application class now 287 lines (43% reduction from 500+)
- ChatLoopOrchestrator, InputProcessor, BackgroundWorkerManager, SessionStatistics extracted
- Formatter decomposed into specialized sub-formatters
- WorkerToken and SpinnerState patterns implemented
- Still has 6 distinct responsibilities:
  1. REPL loop management
  2. Initialization orchestration (6 initialization methods)
  3. Critical section tracking (3 methods)
  4. Shutdown coordination
  5. Console I/O management
  6. Signal handling

**Remaining Work**:
- Extract `SystemLifecycle` class:
  - Shutdown sequence (lines 36-50)
  - Signal handlers (`setup_signal_handlers`)
  - Critical section tracking (lines 167-183)
- Extract `ConversationCoordinator` class:
  - Coordinate InputProcessor and ChatLoopOrchestrator
  - Manage conversation flow at high level
- Streamline Application to be pure REPL controller

**Target State**:
- Application becomes thin REPL controller (< 150 lines)
- Clear separation: lifecycle vs. conversation flow vs. REPL

**Specific Methods to Extract**:
```ruby
# From Application to SystemLifecycle:
- enter_critical_section (lines 167-171)
- exit_critical_section (lines 173-177)
- in_critical_section? (lines 179-183)
- setup_signal_handlers
- shutdown_sequence (ensure block lines 36-50)

# From Application to ConversationCoordinator:
- Coordination between InputProcessor and orchestrator
- High-level conversation state management
```

**Success Criteria**:
- Application class reduced to < 150 lines
- Each extracted class has < 200 lines
- All existing tests pass
- No behavior changes (pure refactoring)
- Each class can be tested independently

---

### Goal 2: Replace Polling with Event-Based Message Display

**Priority**: HIGH

**Current State**:
- Formatter polls History database every 100ms for new messages
- InputProcessor waits in busy loop checking for completion
- Inefficient: repeated database queries
- Latency: 100ms minimum delay for message display
- Tight coupling: Formatter depends on History internals

**Justification**:
- Polling is wasteful - most queries return no new messages
- 100ms latency is noticeable to users
- Tight coupling makes it hard to change message storage
- Adding new message observers requires modifying Formatter
- Difficult to add features like message streaming or progress updates

**Target State**:
- Implement Observer/Event pattern for message lifecycle
- Create MessageBus or EventEmitter class
- Orchestrators publish events when messages are created
- Formatter subscribes to message events
- No polling - immediate notification

**Design Approach**:
```ruby
class MessageBus
  def initialize
    @subscribers = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new
  end

  def subscribe(event_type, &handler)
    @mutex.synchronize do
      @subscribers[event_type] << handler
    end
  end

  def publish(event_type, data)
    handlers = @mutex.synchronize { @subscribers[event_type].dup }
    handlers.each { |handler| handler.call(data) }
  end
end

# Events:
# - :message_created
# - :message_updated
# - :exchange_started
# - :exchange_completed
# - :tool_call_started
# - :tool_call_completed
```

**Integration Points**:
- ChatLoopOrchestrator publishes message events
  - After `history.add_message()` calls
  - Replace `formatter.display_message_created()` with event publish
- ToolCallOrchestrator publishes tool events
  - After tool execution completes
  - Replace direct formatter calls with event publish
- Formatter subscribes to display events
  - Remove `wait_for_completion` polling loop
  - Remove `display_new_messages` polling
  - Subscribe to message bus in constructor
- History still persists, but doesn't drive display

**Code Changes Required**:
1. Create `MessageBus` class (new file: lib/nu/agent/message_bus.rb)
2. Update `ChatLoopOrchestrator`:
   - Add `@message_bus` parameter to constructor
   - Replace `formatter.display_message_created` with `message_bus.publish(:message_created, ...)`
3. Update `Formatter`:
   - Remove `wait_for_completion` method
   - Remove `display_new_messages` method
   - Add `subscribe_to_events` method that registers handlers
   - Remove `@last_message_id` tracking
4. Update `InputProcessor`:
   - Remove polling/waiting logic
   - Use different mechanism to wait for orchestrator thread completion

**Success Criteria**:
- No polling loops in Formatter or InputProcessor
- Message display latency < 10ms (vs 100ms)
- New observers can be added without modifying publishers
- All existing tests pass
- Thread-safe event delivery

---

### Goal 3: Add State Pattern to ConsoleIO

**Priority**: MEDIUM

**Current State**:
- State tracked with `@mode` variable (`:input` or `:spinner`)
- State transitions scattered across multiple methods
- Easy to create invalid states

**Justification**:
- Current approach makes valid state transitions unclear
- Bug-prone: easy to miss state checks
- Hard to reason about what states are valid
- Adding new states (e.g., TUI mode) requires touching many methods
- Testing state transitions is difficult

**Target State**:
- Explicit State pattern with state classes
- Clear state transition rules
- Invalid transitions prevented
- Each state encapsulates its behavior

**Design Approach**:
```ruby
class ConsoleIO
  class State
    def show_spinner(console); raise NotImplementedError; end
    def hide_spinner(console); raise NotImplementedError; end
    def readline(console, prompt); raise NotImplementedError; end
    def puts(console, text); raise NotImplementedError; end
  end

  class InputState < State
    # Can transition to: SpinnerState
  end

  class SpinnerState < State
    # Can transition to: InputState
  end

  def transition_to(state_class)
    @state = state_class.new
  end
end
```

**Code Changes Required**:
1. Create State classes (new file: lib/nu/agent/console_io/states.rb):
   - `ConsoleIO::State` (abstract base)
   - `ConsoleIO::InputState`
   - `ConsoleIO::SpinnerState`
2. Refactor `ConsoleIO`:
   - Replace `@mode` with `@state`
   - Move `show_spinner` logic into state transition
   - Move `hide_spinner` logic into state transition
   - Each state implements: `show_spinner`, `hide_spinner`, `readline`, `puts`

**Success Criteria**:
- All state tracked by State objects, no `@mode` variable
- State transitions explicit and validated
- Invalid state transitions raise errors
- All existing tests pass
- State transition tests added

---

### Goal 4: Implement Chain of Responsibility for RAG Pipeline

**Priority**: MEDIUM

**Current State**:
- RAG pipeline hardcoded in ChatLoopOrchestrator
- Sequence: spell check → message retrieval → context building
- Cannot reorder or disable stages
- Adding new stages requires modifying orchestrator
- Each stage knows about the next stage

**Justification**:
- Pipeline should be configurable (e.g., disable spell check in tests)
- New RAG stages (e.g., web search, embeddings) require orchestrator changes
- Cannot A/B test different pipeline configurations
- Difficult to test stages in isolation
- Violates Open/Closed Principle

**Target State**:
- Chain of Responsibility pattern for RAG pipeline
- Each stage is independent processor
- Pipeline configured at initialization
- Easy to add/remove/reorder stages

**Design Approach**:
```ruby
class ContextProcessor
  def initialize
    @next_processor = nil
  end

  def set_next(processor)
    @next_processor = processor
    processor
  end

  def process(context)
    result = do_process(context)
    if @next_processor
      @next_processor.process(result)
    else
      result
    end
  end

  protected

  def do_process(context)
    # Override in subclasses
  end
end

class SpellCheckProcessor < ContextProcessor; end
class MessageRetrievalProcessor < ContextProcessor; end
class EmbeddingSearchProcessor < ContextProcessor; end
class ContextBuildingProcessor < ContextProcessor; end

# Configuration
pipeline = SpellCheckProcessor.new
pipeline.set_next(MessageRetrievalProcessor.new)
  .set_next(EmbeddingSearchProcessor.new)
  .set_next(ContextBuildingProcessor.new)
```

**Code Changes Required**:
1. Create processor classes (new directory: lib/nu/agent/context_processors/):
   - `context_processor.rb` - Base class with chain logic
   - `spell_check_processor.rb` - Extract from chat_loop_orchestrator.rb
   - `redacted_ranges_processor.rb` - Extract redacted ranges logic
   - `context_builder_processor.rb` - Builds final document
2. Update `ChatLoopOrchestrator`:
   - Replace `build_rag_content` method with pipeline execution
   - Initialize pipeline in constructor
   - Pass context through pipeline: `@rag_pipeline.process(context)`
3. Configure pipeline:
   - Create pipeline builder method
   - Allow conditional inclusion (e.g., skip spell check if disabled)

**Success Criteria**:
- Each processor is independent, testable class
- Pipeline configurable at runtime
- Can disable stages (e.g., spell check in tests)
- All existing tests pass
- New processor can be added without modifying ChatLoopOrchestrator

---

### Goal 5: Add Decorator Pattern for Tool Cross-Cutting Concerns

**Priority**: LOW (May defer to v0.12)

**Current State**:
- Each tool implements its own error handling
- No consistent logging of tool execution
- No audit trail of tool usage
- No permission checking
- Cross-cutting concerns duplicated across 20+ tools

**Justification**:
- Every new tool must remember to add error handling
- No visibility into tool performance or usage patterns
- Cannot easily add features like "explain what tool will do before executing"
- Security concerns: no way to restrict dangerous tools
- Compliance: no audit trail for sensitive operations

**Target State**:
- Decorator pattern for tool cross-cutting concerns
- Tools focus on core logic only
- Composable decorators for: logging, error handling, permissions, audit, dry-run

**Design Approach**:
```ruby
class ToolDecorator
  def initialize(tool)
    @tool = tool
  end

  def name; @tool.name; end
  def description; @tool.description; end
  def parameters; @tool.parameters; end

  def execute(arguments:, history:, context:)
    @tool.execute(arguments:, history:, context:)
  end
end

class LoggingToolDecorator < ToolDecorator
  def execute(arguments:, history:, context:)
    logger.info("Tool #{name} starting", arguments: arguments)
    start_time = Time.now
    result = super
    duration = Time.now - start_time
    logger.info("Tool #{name} completed", duration: duration)
    result
  end
end

class ErrorHandlingDecorator < ToolDecorator; end
class PermissionCheckDecorator < ToolDecorator; end
class AuditDecorator < ToolDecorator; end
class DryRunDecorator < ToolDecorator; end

# Usage
tool = FileWriteTool.new
tool = LoggingToolDecorator.new(tool)
tool = ErrorHandlingDecorator.new(tool)
tool = AuditDecorator.new(tool)
```

**Success Criteria**:
- Tools have no error handling or logging code
- All tools wrapped with standard decorators
- Can add new decorators without modifying tools
- All existing tests pass
- Decorator behavior testable independently

---

## Implementation Order

Execute goals in this order to minimize conflicts:

1. **Goal 3: State Pattern in ConsoleIO** (self-contained, no dependencies)
2. **Goal 4: Chain of Responsibility for RAG** (self-contained, limited dependencies)
3. **Goal 2: Event-Based Message Display** (affects orchestrators and formatter)
4. **Goal 1: Complete Application Refactoring** (depends on Goals 2 & 3 being complete)
5. **Goal 5: Tool Decorators** (optional, can be deferred to v0.12)

## Testing Strategy

For each goal:

1. **Run existing tests before changes** - Establish baseline
2. **Refactor incrementally** - Small commits, tests pass at each step
3. **Add new tests for new patterns** - State transitions, event delivery, etc.
4. **Run full test suite after changes** - No regressions
5. **Manual testing** - Run agent, verify behavior unchanged

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/nu/agent/application_console_integration_spec.rb

# Run tests for a specific goal
bundle exec rspec spec/nu/agent/console_io_spec.rb

# Run with coverage
COVERAGE=true bundle exec rspec
```

## Rollback Plan

Each goal should be completed in a feature branch:

- `feature/state-pattern-console-io`
- `feature/rag-pipeline-chain`
- `feature/event-based-messages`
- `feature/complete-application-refactor`
- `feature/tool-decorators`

If issues arise:
1. Identify which goal caused the issue
2. Revert that branch
3. Fix issue in isolation
4. Retry

## Success Metrics

### Code Quality Metrics
- Application class: 287 lines → < 150 lines (further 48% reduction target)
- ConsoleIO: 626 lines → < 400 lines (with State pattern)
- Average class size: maintained or reduced
- Cyclomatic complexity: reduced by 20%
- Test coverage: maintained at current high level
- RuboCop violations: maintain zero violations

### Performance Metrics
- Message display latency: 100ms → < 10ms
- Database query count: reduced by 50% (no polling)
- Memory usage: no change or slight reduction

### Maintainability Metrics
- New developers can understand Application class in < 5 minutes
- Adding new RAG stage: < 30 minutes
- Adding new tool decorator: < 15 minutes
- Time to diagnose threading issues: reduced by 30%

## Risks and Mitigations

### Risk 1: Breaking Thread Safety
**Mitigation**:
- Review all mutex usage carefully
- Add thread safety tests
- Test with concurrent operations

### Risk 2: Event Bus Performance Overhead
**Mitigation**:
- Profile event delivery
- Use thread-safe queue if needed
- Consider async event delivery for non-critical events

### Risk 3: State Pattern Increases Complexity
**Mitigation**:
- Keep state transitions simple
- Document state diagram
- Provide clear error messages for invalid transitions

### Risk 4: Too Much Refactoring at Once
**Mitigation**:
- Work incrementally, one goal at a time
- Commit after each goal completion
- Run tests frequently

## New Files to Create

This section lists all new files that will be created, organized by goal:

**Goal 1: Complete Application Refactoring**
```
lib/nu/agent/system_lifecycle.rb
lib/nu/agent/conversation_coordinator.rb

spec/nu/agent/system_lifecycle_spec.rb
spec/nu/agent/conversation_coordinator_spec.rb
```

**Goal 2: Event-Based Messages**
```
lib/nu/agent/message_bus.rb

spec/nu/agent/message_bus_spec.rb
```

**Goal 3: State Pattern in ConsoleIO**
```
lib/nu/agent/console_io/state.rb
lib/nu/agent/console_io/input_state.rb
lib/nu/agent/console_io/spinner_state.rb

spec/nu/agent/console_io/states_spec.rb
```

**Goal 4: RAG Pipeline Chain**
```
lib/nu/agent/context_processors/context_processor.rb
lib/nu/agent/context_processors/spell_check_processor.rb
lib/nu/agent/context_processors/redacted_ranges_processor.rb
lib/nu/agent/context_processors/context_builder_processor.rb

spec/nu/agent/context_processors/context_processor_spec.rb
spec/nu/agent/context_processors/spell_check_processor_spec.rb
spec/nu/agent/context_processors/redacted_ranges_processor_spec.rb
spec/nu/agent/context_processors/pipeline_spec.rb
```

**Goal 5: Tool Decorators (Optional)**
```
lib/nu/agent/tool_decorators/tool_decorator.rb
lib/nu/agent/tool_decorators/logging_decorator.rb
lib/nu/agent/tool_decorators/error_handling_decorator.rb
lib/nu/agent/tool_decorators/permission_check_decorator.rb
lib/nu/agent/tool_decorators/audit_decorator.rb

spec/nu/agent/tool_decorators/logging_decorator_spec.rb
spec/nu/agent/tool_decorators/error_handling_decorator_spec.rb
spec/nu/agent/tool_decorators/decorator_composition_spec.rb
```

**Don't forget to update lib/nu/agent.rb** to require all new files!

## Definition of Done

Version 0.11 is complete when:

- ✅ All 5 goals completed (or 4 if Goal 5 deferred to v0.12)
- ✅ All existing tests pass
- ✅ New tests added for new patterns
- ✅ Manual testing shows no behavior changes
- ✅ Code review completed
- ✅ Documentation updated (architecture-analysis.md, design.md)
- ✅ Changelog updated
- ✅ Version bumped to 0.11.0

## Notes for Future Developer

When you start this work:

1. Read the required documents first
2. Don't try to do everything at once - follow implementation order
3. Each goal should be achievable in 2-4 hours
4. Commit frequently, keep tests passing
5. If you find additional issues, document them but stay focused on plan goals
6. Ask questions if requirements are unclear (update this plan with answers)
7. Remember: this is pure refactoring - no behavior changes
8. Follow TDD practices from AGENT.md - write tests first!

Good luck! This refactoring will continue improving the codebase maintainability.
