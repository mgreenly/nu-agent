# RuboCop Lint Fixes Progress

**Current Status:** 167 total offenses (down from 289 initial)
**Progress:** 122 offenses fixed (42% reduction)
**Phase 2 Status:** 10/14 completed (71%)

## Completed ✓

- [x] **Auto-correctable offenses** - 16 fixed
  - Removed useless variable assignments
  - Fixed automatic line breaks

- [x] **Layout/LineLength** - 42 fixed (42 → 0, 100% complete)
  - Used heredocs for multi-line strings
  - Shortened variable names in code
  - Broke long descriptions across lines
  - Extracted intermediate variables

- [x] **Lint/UnusedMethodArgument** - 34 fixed (34 → 0, 100% complete)
  - Removed unused parameters from method signatures
  - Replaced unused params with `**` splat

- [x] **Style/ComparableClamp** - 5 fixed (5 → 0, 100% complete)
  - Replaced `[[x, min].max, max].min` with `x.clamp(min, max)`

- [x] **Style/FormatString** - 5 fixed (9 → 4 → 0, 100% complete)
  - Replaced `"%.2f" % value` with `format("%.2f", value)`

- [x] **Style/FormatStringToken** - 4 fixed (4 → 0, 100% complete)
  - Changed `%s` to `%<name>s` for annotated tokens

- [x] **Lint/DuplicateBranch** - 3 fixed (3 → 0, 100% complete)
  - Merged duplicate conditional branches
  - Combined duplicate case statements

- [x] **Naming/AccessorMethodName** - 2 fixed (2 → 0, 100% complete)
  - Renamed `get_all_conversations` → `all_conversations`
  - Renamed `get_all_man_pages` → `all_man_pages`

- [x] **Gemspec/RequiredRubyVersion** - 1 fixed (1 → 0, 100% complete)
  - Updated TargetRubyVersion in .rubocop.yml from 3.0 to 3.1

- [x] **Safe auto-correctable** - 6 additional fixes
  - Layout/ArgumentAlignment (2)
  - Layout/TrailingWhitespace (2)
  - Style/MultilineIfModifier (2)

## Priority 1: Low Complexity (Quick Wins) ✓

### All 73 offenses fixed! (100% complete)

## Priority 2: Medium Complexity (Refactoring)

### Completed: 10/14 (71%)  |  Remaining: 4 offenses

- [x] **Lint/MissingSuper** (1 → 0) ✓
  - Fixed `lib/nu/agent/clients/xai.rb:28` - now calls `super(api_key: api_key, model: model)`

- [x] **Metrics/ParameterLists** (9 → 0) ✓
  - Refactored using `**options` / `**context` / `**attributes` patterns
  - Fixed methods:
    - History#add_message (15 → 4 params) - used `**attributes` for optional params
    - FileGrep#build_ripgrep_command (9 → 3 params) - used `**options`
    - Application#tool_calling_loop (8 → 3 params) - used `**context`
    - Application#chat_loop (6 → 3 params) - used `**context`
    - Formatter#initialize (7 → 3 params) - used `**config`
    - Formatter#display_message_created (6 → 2 params) - used `**details`
    - Application#summarize_conversations (6 → 2 params) - used `**context`
    - 2 Thread.new blocks (6 → 4 params each) - passed context hash

- [ ] **Metrics/ClassLength** (4 → 4, partially improved)
  - ⚠️ **Requires major architectural refactoring** - extracting entire classes/modules
  - Status:
    - `lib/nu/agent/application.rb` (1236/250 lines, 986 over) ❌ - Extract command handlers, summarizer, man indexer
    - `lib/nu/agent/history.rb` (751/250 lines, 501 over) ❌ - Extract query builder, schema manager
    - `lib/nu/agent/formatter.rb` (338/250 lines, 88 over) ⚠️ - Partially refactored, needs module extraction
    - `lib/nu/agent/tools/file_edit.rb` (331/250 lines, 81 over) ⚠️ - Partially refactored (333→331)
  - Attempted fixes:
    - Formatter: Extracted 5 helper methods from `display_message_created` and `display_tool_result`
    - FileEdit: Extracted 4 helper methods from `execute` (parse_operations, log_operation_mode, etc.)
    - **Conclusion:** Method extraction insufficient - need class/module extraction for significant reduction

## Priority 3: High Complexity (Architecture)

### Remaining: 162 offenses

These require significant refactoring and should be addressed through:
1. Extract Method refactoring
2. Extract Class refactoring
3. Simplify conditional logic
4. Reduce nesting depth

- [ ] **Metrics/MethodLength** (50) - Methods >25 lines
  - Extract helper methods
  - Break into smaller focused methods
  - Effort: High

- [ ] **Metrics/AbcSize** (44) - Complex methods (Assignment/Branch/Condition)
  - Simplify logic
  - Extract helper methods
  - Effort: High

- [ ] **Metrics/CyclomaticComplexity** (27) - Too many conditionals
  - Simplify branching logic
  - Use polymorphism or strategy pattern
  - Effort: High

- [ ] **Metrics/PerceivedComplexity** (27) - Complex nested logic
  - Flatten nesting
  - Early returns
  - Guard clauses
  - Effort: High

- [ ] **Metrics/BlockLength** (9) - Blocks >25 lines
  - Extract methods from blocks
  - Effort: Medium-High

- [ ] **Metrics/BlockNesting** (4) - Too deeply nested blocks
  - Flatten nesting
  - Extract methods
  - Effort: High

## Recommended Fix Order

1. ✅ **Phase 1 (Low-hanging fruit):** Fix Priority 1 items - COMPLETE!
   - Fixed all 73 offenses (100% complete)
   - Reduced total from 200 → 175 (25 offenses fixed)
   - Actual time: ~1 hour

2. **Phase 2 (Structural improvements):** Address Priority 2 items - 71% COMPLETE
   - **Completed:** 10/14 offenses fixed
     - Lint/MissingSuper (1 fixed)
     - Metrics/ParameterLists (9 fixed)
   - **Remaining:** 4 Metrics/ClassLength violations
     - Blocked: Requires architectural changes (class/module extraction)
     - Should be combined with Phase 3 refactoring
   - Actual time: ~2 hours
   - Impact: Reduced from 175 → 167 offenses (8 fixed, 2 improved)

3. **Phase 3 (Architecture):** Tackle Priority 3 items (164 offenses)
   - High impact, high effort
   - Requires careful planning and testing
   - Should be done incrementally
   - **Estimated time:** Multiple days/weeks
   - **Items:**
     - Metrics/MethodLength (51) - Methods >25 lines
     - Metrics/AbcSize (46) - Complex methods
     - Metrics/CyclomaticComplexity (27) - Too many conditionals
     - Metrics/PerceivedComplexity (27) - Complex nested logic
     - Metrics/BlockLength (9) - Blocks >25 lines
     - Metrics/BlockNesting (4) - Too deeply nested
   - **Worst offenders:**
     - Application#handle_command (312 lines, 4 violations)
     - Application#index_man_pages (117 lines, 4 violations)
     - Application#tool_calling_loop (111 lines, 4 violations)
     - Application#summarize_conversations (107 lines, 4 violations)

## 🚀 Next Steps: Architectural Refactoring (Start Fresh)

### Why Start with application.rb (the root)?

**Decision:** Refactor from the **core outward**, not leaves inward.

**Rationale:**
1. **Avoid churn** - Fixing leaves (tools, formatters) first means:
   - We might change their interfaces when we refactor the core anyway
   - Double work, wasted effort
   - Inconsistent patterns across codebase

2. **God Object anti-pattern** - `application.rb` (1236 lines) does EVERYTHING:
   - Command handling (312-line method!)
   - Orchestration (tool calling, chat loops)
   - Man page indexing (117 lines)
   - Conversation summarization (107 lines)
   - Thread management
   - This is the ROOT CAUSE of complexity

3. **Cascading benefits** - Extract from core → establishes patterns → rest follows naturally

4. **Don't move the problem** - Moving methods to modules just hides complexity
   - Need REAL architectural changes
   - Break responsibilities into proper classes
   - Each class solves ONE problem

### Recommended Extraction Order

#### Phase 1: Extract from application.rb (Priority)

**Target:** Reduce 1236 → ~250 lines by extracting 4 major components:

1. **CommandHandler** (~350 lines)
   - Extract `handle_command` (312 lines) into command pattern
   - Each command becomes a class: `ListCommand`, `InfoCommand`, etc.
   - **Why:** Massive switch statement violates Open/Closed Principle
   - **Benefit:** Add new commands without touching existing code

2. **ManPageIndexer** (~120 lines)
   - Extract `index_man_pages` method
   - Self-contained: parses man pages, builds embeddings
   - **Why:** Different responsibility from app orchestration
   - **Benefit:** Can test/improve indexing independently

3. **ConversationSummarizer** (~110 lines)
   - Extract `summarize_conversations` and background worker logic
   - **Why:** Summarization is a separate concern
   - **Benefit:** Could use different LLM, run separately, etc.

4. **ToolCallOrchestrator** (~120 lines)
   - Extract `tool_calling_loop` (111 lines)
   - Handles LLM tool calling protocol
   - **Why:** Complex protocol logic separate from app lifecycle
   - **Benefit:** Could support different tool calling strategies

**Remaining in Application:** (~250 lines)
- Initialization
- Main REPL loop
- Session management
- Delegating to extracted components

#### Phase 2: Let Other Refactorings Follow

After establishing patterns from application.rb:

- **History** (751 lines) → Extract QueryBuilder, SchemaManager
- **Formatter** (338 lines) → Extract message type formatters
- **Tools** → Apply same patterns consistently

### Key Principle

**"You can't just move the problem to a different file"**

✅ **Good refactoring:** Extract classes with clear single responsibilities
❌ **Bad refactoring:** Move methods to modules just to game metrics

### How to Start Next Session

```bash
# 1. Check current state
bundle exec rubocop --only Metrics/ClassLength
# Should show: application.rb (1236/250)

# 2. Analyze application.rb structure
grep -n "def handle_command" lib/nu/agent/application.rb
# Line 620, 312 lines - this is the main target

# 3. Plan extraction strategy
# Read handle_command, identify all command types
# Design command pattern structure
```

### Success Criteria

- [ ] application.rb < 250 lines
- [ ] Each extracted class < 250 lines
- [ ] Each class has ONE clear responsibility
- [ ] All 255 tests still passing
- [ ] No interfaces changed (backward compatible)

## Notes

- Always run tests after each fix: `bundle exec rspec`
- Commit frequently with clear messages
- Follow TDD for any new code (see AGENT.md)
- Prioritize readability over just fixing metrics
- **Don't just move code - actually improve the design**
