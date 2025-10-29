Nu-Agent v0.16 Plan: Granular Debug Verbosity Control

Last Updated: 2025-10-29
Target Version: 0.16.0
Plan Status: Draft for review

Index
- High-level motivation
- Scope (in)
- Scope (out, future enhancements)
- Key technical decisions
- Verbosity flags
- Implementation phases
  - Phase 1: Add verbosity flags to configuration
  - Phase 2: Implement /verbosity command
  - Phase 3: Update debug output checks
  - Phase 4: Testing and refinement
- Success criteria
- Future enhancements
- Notes

High-level motivation
- Replace single numeric verbosity level (0-6) with granular per-feature verbosity flags.
- Enable users to see debug output for specific features without noise from others.
- Maintain /debug [on|off] as global master switch that controls all debug output.
- Each feature area gets its own verbosity flag with numeric levels (0=off, 1=minimal, 2+=verbose).
- Provide fine-grained control over debug output without overwhelming users.

Scope (in)
- Create individual `verbosity_*` flags for each debug output area:
  - `verbosity_thread_lifecycle` - Worker thread start/stop events
  - `verbosity_message_tracking` - Message creation/routing notifications
  - `verbosity_llm_warnings` - LLM API warnings and edge cases
  - `verbosity_tool_call` - Tool invocation display with arguments
  - `verbosity_tool_result` - Tool execution results display
  - `verbosity_llm_requests` - Full LLM request payloads
  - `verbosity_statistics` - Token counts, spending, timing info
  - `verbosity_spell_checker` - Spell checker messages
  - `verbosity_search_commands` - Search tool command details
- Store all verbosity flags in appconfig database (default: 0).
- Implement `/verbosity <flag_name> <level>` command to set individual flags.
- Implement `/verbosity all <level>` to set all flags to same level.
- Implement `/verbosity list` to show all flags and their current values.
- Update all debug output to check: `if @debug && verbosity_for(:flag_name) > 0`.
- No debug output should bypass the flag system - everything must be controllable.

Scope (out, future enhancements)
- Verbosity presets (e.g., `/verbosity preset developer` sets common flags).
- Per-conversation verbosity overrides.
- Environment variable support for initial verbosity settings.
- Wildcard flag setting (e.g., `/verbosity tool_* 1`).
- Output filtering or redirection for debug messages.
- Time-based verbosity (automatically increase verbosity after N seconds).

Key technical decisions
- Flag naming convention: `verbosity_<feature_name>` (underscore, lowercase).
- Command syntax: `/verbosity <feature_name> <level>` (no `verbosity_` prefix in command).
- Flag storage: Individual columns in appconfig table for each flag.
- Default value: All flags default to 0 (silent even when debug=on).
- Master switch: `/debug on` required for ANY debug output; flags only work when debug is on.
- Flag access method: Add `verbosity_for(flag_name)` helper that returns numeric level.
- Backward compatibility: Remove single `verbosity` column after migration.
- List display: Show flags grouped by category (messages, tools, llm, misc).

Verbosity flags

Core flags (all default to 0):
- `verbosity_thread_lifecycle` - Thread start/stop events
  - Level 0: No output
  - Level 1: Thread start/stop only
  - Level 2+: Reserved for future (thread state changes, etc.)

- `verbosity_message_tracking` - Message creation/flow
  - Level 0: No output
  - Level 1: Basic message in/out notifications
  - Level 2: Add role, actor, content preview (30 chars)
  - Level 3+: Extended previews (100 chars)

- `verbosity_llm_warnings` - LLM edge cases
  - Level 0: No output
  - Level 1: Show warnings (empty responses, etc.)
  - Level 2+: Reserved for future

- `verbosity_tool_call` - Tool invocations
  - Level 0: No output
  - Level 1: Show tool name and brief args
  - Level 2: Show full arguments, no truncation
  - Level 3+: Reserved for future (timing, caching info)

- `verbosity_tool_result` - Tool outputs
  - Level 0: No output
  - Level 1: Show tool name and brief result
  - Level 2: Show full results, no truncation
  - Level 3+: Reserved for future

- `verbosity_llm_requests` - Full LLM payloads
  - Level 0: No output
  - Level 1: Show message count, token estimate
  - Level 2: Show full request with messages
  - Level 3: Add tool definitions
  - Level 4+: Reserved for future (raw JSON, etc.)

- `verbosity_statistics` - Metrics and timing
  - Level 0: No output
  - Level 1: Show basic token/cost summary
  - Level 2: Add timing, cache hits, detailed breakdown
  - Level 3+: Reserved for future

- `verbosity_spell_checker` - Spell check activity
  - Level 0: No output (even in debug)
  - Level 1: Show spell checker messages
  - Level 2+: Reserved for future

- `verbosity_search_commands` - Search tool internals
  - Level 0: No output
  - Level 1: Show ripgrep command being executed
  - Level 2: Add search stats, file counts
  - Level 3+: Reserved for future

Implementation phases

Phase 1: Add verbosity flags to configuration (1.5 hrs)
Goal: Create database schema and configuration support for all verbosity flags.
Tasks
- Add migration to add verbosity flag columns to appconfig:
  - `verbosity_thread_lifecycle INTEGER DEFAULT 0`
  - `verbosity_message_tracking INTEGER DEFAULT 0`
  - `verbosity_llm_warnings INTEGER DEFAULT 0`
  - `verbosity_tool_call INTEGER DEFAULT 0`
  - `verbosity_tool_result INTEGER DEFAULT 0`
  - `verbosity_llm_requests INTEGER DEFAULT 0`
  - `verbosity_statistics INTEGER DEFAULT 0`
  - `verbosity_spell_checker INTEGER DEFAULT 0`
  - `verbosity_search_commands INTEGER DEFAULT 0`
- Update Configuration struct in configuration_loader.rb to include all flags.
- Update configuration_loader.rb to load all flags from database (default: 0).
- Add `verbosity_for(flag_name)` helper method to Application class.
- Update Application class to expose all verbosity flags.
Testing
- Verify migration runs cleanly on empty database.
- Verify default values are 0 for all flags.
- Verify configuration_loader reads flags correctly.
- Test verbosity_for method returns correct values.

Phase 2: Implement /verbosity command (1 hr)
Goal: Create command to view and modify verbosity flags.
Tasks
- Update existing verbosity_command.rb or create new verbosity_flags_command.rb:
  - Handle `/verbosity list` - show all flags with current values
  - Handle `/verbosity <flag_name> <level>` - set individual flag
  - Handle `/verbosity all <level>` - set all flags to same level
  - Handle `/verbosity <flag_name>` - show current value of one flag
- Display flags in organized format (grouped by category).
- Validate flag names (reject invalid flags with helpful error).
- Validate levels (must be non-negative integers).
- Update appconfig in database when flags change.
- Show confirmation message after changes.
Testing
- Test `/verbosity list` shows all 9 flags.
- Test setting individual flags updates database.
- Test `/verbosity all 1` sets all flags to 1.
- Test invalid flag name shows helpful error.
- Test non-numeric level shows error.

Phase 3: Update debug output checks (2 hrs)
Goal: Replace all `if @debug` checks with `if @debug && verbosity_for(:flag) > 0`.
Tasks
- Update formatter.rb:
  - display_spell_checker_message: check verbosity_spell_checker
  - display_tool_result: check verbosity_tool_result
  - display_thread_event: check verbosity_thread_lifecycle
  - display_message_created: check verbosity_message_tracking
  - display_debug_tool_calls: check verbosity_tool_call
  - display_content_or_warning (empty response): check verbosity_llm_warnings
- Update llm_request_formatter.rb:
  - display method: check verbosity_llm_requests
  - Respect levels (1=basic, 2=full messages, 3=with tools)
- Update tool_call_formatter.rb:
  - Respect verbosity_tool_call levels (1=basic, 2=full args)
- Update tool_result_formatter.rb:
  - Respect verbosity_tool_result levels (1=basic, 2=full result)
- Update session_statistics.rb:
  - Check verbosity_statistics instead of just @debug
- Update file_grep.rb:
  - Check verbosity_search_commands for command debug output
- Ensure NO debug output exists that doesn't check a verbosity flag.
Testing
- Enable debug, set all flags to 0: verify complete silence.
- Enable debug, set one flag to 1: verify only that feature outputs.
- Test each flag individually at different levels.
- Verify no "orphaned" debug output that bypasses flags.

Phase 4: Testing and refinement (30 min)
Goal: Comprehensive testing and documentation.
Tasks
- Manual testing scenarios:
  - Start with `/debug on`, all flags at 0: expect silence.
  - Set `/verbosity tool_call 1`: see tool invocations only.
  - Set `/verbosity all 2`: see verbose output from all features.
  - Mix levels: some at 0, some at 1, some at 2.
- Test that existing behavior works when flags are set appropriately.
- Update help text for `/debug` command to mention verbosity flags.
- Update help text for `/verbosity` command with examples.
- Document flag meanings in help or README.
Testing
- Run existing test suite, ensure no regressions.
- Verify backwards compatibility (old debug/verbosity behavior no longer needed).
- Document any edge cases or gotchas.

Success criteria
- Functional: Users can control debug output per-feature using verbosity flags.
- Granular: Each of 9 features has independent control (0, 1, 2+ levels).
- Silent by default: `/debug on` with default flags (all 0) produces no output.
- Master switch: `/debug off` disables all output regardless of flag values.
- Easy discovery: `/verbosity list` shows all available flags clearly.
- Bulk control: `/verbosity all 1` provides quick way to enable everything.
- No leaks: Every debug output is controlled by a flag, no exceptions.

Future enhancements
- Verbosity presets: `/verbosity preset minimal` (set common flags for typical use).
- Verbosity profiles: Save/restore verbosity configurations by name.
- Per-conversation overrides: Set flags for current conversation only.
- Wildcard support: `/verbosity tool_* 1` sets tool_call and tool_result.
- Environment variables: `NU_AGENT_VERBOSITY_TOOL_CALL=1` for defaults.
- Dynamic adjustment: Auto-increase verbosity if operation takes > 30s.
- Output targeting: Send debug output to separate file or stream.
- Time-stamping: Add timestamps to debug output for performance analysis.
- Color coding: Different colors for different verbosity flags.

Notes
- The migration from single verbosity (0-6) to multiple flags is a breaking change for users who rely on specific verbosity levels, but provides much better control.
- Users who want "old verbosity 4" behavior can use `/verbosity all 1` as approximation.
- Flag granularity can be adjusted later (add new flags, split existing ones) without changing the overall architecture.
- Level meanings (0/1/2) can vary per flag based on what makes sense for that feature.
- Most flags will typically be set to 0 or 1; level 2+ is for deep debugging.
- The `verbosity_for(:flag)` helper could be extended to support flag aliases or shortcuts in future.
- Consider adding `/vv` (verbosity viewer) as shorthand for `/verbosity list`.

Example usage:
```
# Enable debug but keep it quiet by default
> /debug on
Debug mode enabled

# See what flags are available
> /verbosity list
Verbosity flags (all default to 0):
  Messages:
    thread_lifecycle: 0
    message_tracking: 0
    llm_warnings: 0
  Tools:
    tool_call: 0
    tool_result: 0
  LLM:
    llm_requests: 0
    statistics: 0
  Other:
    spell_checker: 0
    search_commands: 0

# Enable just tool call output
> /verbosity tool_call 1
Set verbosity_tool_call to 1

# Now tool calls show up during operation
> search for authentication code
[Tool] file_grep: pattern="authentication" ...
... results ...

# Enable everything at minimal level
> /verbosity all 1
Set all verbosity flags to 1

# Increase message tracking to verbose level
> /verbosity message_tracking 2
Set verbosity_message_tracking to 2
```
