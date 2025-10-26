# RuboCop Lint Fixes Progress

**Current Status:** 154 total offenses (down from 289 initial)
**Progress:** 135 offenses fixed (47% reduction)

## ✅ Completed Phases

**Phase 1: Low Complexity** - 73 offenses fixed (100%)
- Auto-correctable: 16 | Layout/LineLength: 42 | Lint/UnusedMethodArgument: 34
- Style/ComparableClamp: 5 | Style/FormatString: 5 | Style/FormatStringToken: 4
- Lint/DuplicateBranch: 3 | Naming/AccessorMethodName: 2 | Others: 8

**Phase 2: Medium Complexity** - 10/14 fixed (71%)
- ✅ Lint/MissingSuper: 1 → 0 (xai.rb now calls super)
- ✅ Metrics/ParameterLists: 9 → 0 (using `**options`/`**context`/`**attributes`)
  - History#add_message: 15→4 params | FileGrep: 9→3 | Application: 8→3, 6→3 | Formatter: 7→3, 6→2
- ⚠️ **Metrics/ClassLength: 4 remaining** (requires architectural refactoring - see Next Steps)

**Priority 3: High Complexity** - 149 remaining
- Metrics/MethodLength: 46 | AbcSize: 40 | CyclomaticComplexity: 25 | PerceivedComplexity: 25
- BlockLength: 8 | BlockNesting: 1
- **Top offenders:** Application#handle_command (312 lines), tool_calling_loop (111), chat_loop (89)

**✅ Extraction #1 Complete: ManPageIndexer**
- **Lines reduced:** Application: 1236 → 1113 (123 lines extracted)
- **New class:** ManPageIndexer (202 lines, passes RuboCop)
- **Tests:** 5 new specs, all passing
- **Impact:** Removed 10 offenses from application.rb

**✅ Extraction #2 Complete: ConversationSummarizer**
- **Lines reduced:** Application: 1113 → 991 (122 lines extracted)
- **New class:** ConversationSummarizer (182 lines)
- **Tests:** 7 new specs, all passing
- **Impact:** Removed 8 offenses from application.rb, added 5 to new class (net -3)

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
