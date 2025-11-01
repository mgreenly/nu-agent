# Verbosity System Improvements - Notes

## Overview
This document collects ideas and notes for improving the `/verbosity` command and subsystem.

## Current State
- `/verbosity` command exists with subsystem support
- Subsystems: messages, thread, console
- Each subsystem has numeric levels (0, 1, 2, etc.)
- Thread verbosity: Phase 3 complete (see plan-thread-verbosity.md)

## Ideas & Improvements

### 1. Additional Subsystems
_What other subsystems could benefit from verbosity control?_

### 2. UX Improvements
_How can we make the verbosity command easier to use?_

#### Value Clamping
When a user provides a value outside the valid range for a subsystem, clamp it to the nearest valid value instead of erroring.

**Examples**:
- `/verbosity llm 9` where llm supports 0-1 → clamps to 1
- `/verbosity llm -3` where llm supports 0-1 → clamps to 0
- `/verbosity messages 100` where messages supports 0-2 → clamps to 2

**Benefits**:
- More forgiving UX - "just make it more verbose" works
- Users don't need to remember exact max values
- Natural behavior: bigger numbers = more verbose, smaller/negative = less verbose

### 3. Level Definitions
_Should we standardize what each level means across subsystems?_

### 4. Performance
_Any performance implications of checking verbosity?_

### 5. Documentation
_What documentation do users need?_

## Working as Expected

### `/verbosity spell` (spell check)
- ✓ Appears to work correctly
- Controls spell checker output as expected

### `/verbosity help`
- ✓ Shows help level for each subsystem
- Provides useful overview of available subsystems and their current settings

## Known Issues

### `/verbosity llm` appears to do nothing
- Command accepts the subsystem but doesn't seem to affect LLM-related output
- Need to verify:
  - Is the subsystem implemented?
  - What output should it control?
  - Is it being checked anywhere in the codebase?

### `/verbosity tool 0` still shows tool use responses
- Setting `/verbosity tool 0` doesn't suppress tool use/response output
- Still seeing messages like:
  - `[Tool Use Response] (Batch 1/Thread 1) database_tables [Start: 09:09:08.521, End: 09:09:08.526, Duration: 5ms]`
  - `[Tool Use Response] database_query`
- Expected behavior: tool 0 should suppress all tool-related output
- Need to verify if the tool verbosity check is being used correctly in the formatter

### `/verbosity tools help` doesn't display help
- Command `/verbosity tools help` does not show help information for the tools subsystem
- Expected: Should display available levels and what each level controls
- General `/verbosity help` works, but subsystem-specific help does not

### `/verbosity tools 1` shows too much information
- Currently shows debug output like:
  - `[DEBUG] Analyzing 1 tool calls for dependencies...`
  - `[DEBUG] Created 1 batch from 1 tool call`
- Expected: Level 1 should just show the tool name
- The verbose debug info should be at a higher level (maybe level 2 or 3)

### API request/response debug values in wrong subsystem
- API request/response debug output is currently showing as part of tool verbosity
- Should be moved to messages verbosity instead
- Messages verbosity at some level should show:
  - API cycle (request/response timing and details)
  - Database cycle for messages (message persistence operations)
- This separation makes more sense: tools = tool execution, messages = API/LLM message lifecycle

## Open Questions

### `/verbosity thread` scope
- Currently appears to only affect orchestrator thread output
- Should it also control all background thread messages?
- Need to determine:
  - Is current behavior (orchestrator only) intentional?
  - What other background threads exist that should respect this setting?
  - Are there cases where we'd want different verbosity for different thread types?

### Tool batch analyzer verbosity level
- Need to decide at what level the tool batch analyzer output should be shown
- Messages like:
  - `[DEBUG] Analyzing 1 tool calls for dependencies...`
  - `[DEBUG] Created 1 batch from 1 tool call`
- Consideration: Maybe this should be shown at level 1 (before individual tool names)?
- Need to determine the right progression of information across levels

## Implementation Ideas

### Reorder stats verbosity levels
`/verbosity stats` works but the level order should be changed to be more intuitive:

**Proposed levels**:
- Level 0: No stats output
- Level 1: Show time only
- Level 2: Show time + tokens used
- Level 3: Show time + tokens + spend

**Rationale**:
- Time is the most basic/least detailed stat
- Token usage is more detailed
- Spend is the most detailed (requires knowing both tokens and pricing)
- Each level builds on the previous, adding more information

## Related Files
- `lib/nu_agent/commands/verbosity_command.rb` - Main command implementation
- `lib/nu_agent/formatter.rb` - Uses verbosity for output control
- `docs/dev/plan-thread-verbosity.md` - Thread subsystem implementation
