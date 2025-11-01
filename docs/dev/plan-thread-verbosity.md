# Thread Verbosity Control

## Goal
Add `/verbosity thread` subsystem to control thread start/stop debug messages independently from global debug mode.

## Current State
- Thread messages (via `display_thread_event`) only check `@debug` flag
- No granular control - either all thread messages or none
- Affects: Orchestrator threads, background workers, parallel execution, spell checker, RAG, etc.

## Design
Add new "thread" subsystem with levels:
- Level 0: No thread debug output
- Level 1: Show thread start/stop messages

## Implementation Phases

### Phase 1: Add thread subsystem to VerbosityCommand
- [ ] Write failing test for thread subsystem in SUBSYSTEMS hash
- [ ] Add "thread" subsystem to SUBSYSTEMS constant
- [ ] Verify test passes
- [ ] Run `rake test`, `rake lint`, `rake coverage`
- [ ] Commit

### Phase 2: Update display_thread_event to use thread verbosity
- [ ] Write failing test for display_thread_event checking thread verbosity at level 0
- [ ] Write failing test for display_thread_event checking thread verbosity at level 1
- [ ] Add thread_verbosity helper method to Formatter (similar to messages_verbosity)
- [ ] Update display_thread_event to check thread verbosity instead of @debug
- [ ] Verify tests pass
- [ ] Run `rake test`, `rake lint`, `rake coverage`
- [ ] Commit

### Phase 3: Update existing tests
- [ ] Review all formatter_spec tests that stub display_thread_event
- [ ] Update tests to properly stub thread_verbosity if needed
- [ ] Ensure all tests pass
- [ ] Run `rake test`, `rake lint`, `rake coverage`
- [ ] Commit

### Phase 4: Manual validation
- [ ] Test `/verbosity` shows thread subsystem
- [ ] Test `/verbosity thread` shows current level
- [ ] Test `/verbosity thread 0` hides thread messages in debug mode
- [ ] Test `/verbosity thread 1` shows thread messages
- [ ] Test with orchestrator threads
- [ ] Test with background workers (if applicable)

## Success Criteria
- All tests pass
- No lint violations
- Coverage maintained
- Thread messages controlled independently of global debug flag
