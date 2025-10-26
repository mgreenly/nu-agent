# RuboCop Lint Fixes Progress

**Current Status:** 151 total offenses (down from 289 initial)
**Progress:** 138 offenses fixed (48% reduction)

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

**Priority 3: High Complexity** - 146 remaining
- Metrics/MethodLength: 44 | AbcSize: 38 | CyclomaticComplexity: 24 | PerceivedComplexity: 24
- BlockLength: 7 | BlockNesting: 1
- **Top offenders:** Application#handle_command (312 lines), chat_loop (89), print_info (37)

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

**✅ Extraction #3 Complete: ToolCallOrchestrator**
- **Lines reduced:** Application: 991 → 896 (95 lines extracted)
- **New class:** ToolCallOrchestrator (176 lines)
- **Tests:** 6 new specs, all passing
- **Impact:** Removed 7 offenses from application.rb, added 4 to new class (net -3)

## 📊 Cumulative Extraction Progress

**Overall Impact:**
- Application.rb: **1236 → 896 lines** (340 lines / 27% reduction)
- Total offenses: **289 → 151** (138 fixed / 48% reduction)
- Tests: **260 → 273** (13 new specs added, all passing)

**Extractions Summary:**
| Extraction | Lines Reduced | New Class | Tests | Net Offenses |
|------------|---------------|-----------|-------|--------------|
| ManPageIndexer | 123 | 202 lines | 5 specs | -10 |
| ConversationSummarizer | 122 | 182 lines | 7 specs | -3 |
| ToolCallOrchestrator | 95 | 176 lines | 6 specs | -3 |
| **Total** | **340** | **560 lines** | **18 specs** | **-16** |

## 🎯 Next Priority: CommandHandler Extraction

**Target:** Extract `handle_command` method - the largest remaining complexity

### Current State
- **Location:** `lib/nu/agent/application.rb:496` (as of 2025-10-26)
- **Size:** 312 lines (largest method in application.rb)
- **Complexity:** 70 cyclomatic complexity, 70 perceived complexity
- **Problem:** Massive switch statement handling 15+ different commands

### Why This Matters
1. **Violates Open/Closed Principle** - Can't add new commands without modifying existing code
2. **Single largest offender** - 312 lines in one method
3. **Hard to test** - All commands coupled together
4. **Hard to extend** - Adding new commands requires touching this giant method

### Proposed Solution: Command Pattern

Extract each command into its own class:
- `/debug` → `DebugCommand`
- `/model` → `ModelCommand`
- `/help` → `HelpCommand`
- `/info` → `InfoCommand`
- `/tools` → `ToolsCommand`
- etc.

Each command class implements a common interface:
```ruby
class BaseCommand
  def execute(input, application)
    # Command logic here
  end
end
```

### Expected Impact
- **Lines reduced:** ~350 lines (includes helper methods)
- **Application.rb:** 896 → ~550 lines (38% reduction from current)
- **Offenses removed:** ~4-5 major complexity offenses
- **Final target:** Application.rb < 600 lines (from original 1236)

### How to Start

```bash
# 1. Check current state
bundle exec rubocop --only Metrics/MethodLength lib/nu/agent/application.rb
# Should show: handle_command (312 lines)

# 2. Analyze handle_command structure
grep -n "def handle_command" lib/nu/agent/application.rb
# Current line: 496

# 3. Identify all commands
grep "when\|if.*start_with" lib/nu/agent/application.rb | grep -A1 "def handle_command"
# Lists: /model, /redaction, /summarizer, /spellcheck, /index-man, /debug,
#        /verbosity, /exit, /clear, /tools, /reset, /fix, /migrate-exchanges,
#        /info, /models, /help

# 4. Design command registry pattern
# - CommandRegistry to map command names to classes
# - BaseCommand interface for consistency
# - Extract one command at a time with tests (TDD)
```

### Success Criteria

- [ ] application.rb < 600 lines (from current 896)
- [ ] Each command class < 100 lines
- [ ] Each command has isolated tests
- [ ] All 273+ tests passing
- [ ] Command pattern allows easy addition of new commands
- [ ] No changes to user-facing behavior

## 🚀 After CommandHandler

Once CommandHandler is extracted, application.rb should be ~550-600 lines with:
- ✅ Worker management (ManPageIndexer, ConversationSummarizer)
- ✅ Tool calling protocol (ToolCallOrchestrator)
- ✅ Command handling (CommandHandler)
- Remaining: Initialization, REPL loop, chat_loop, session management

**Then consider:**
- **History** (751 lines) → Extract QueryBuilder, SchemaManager
- **Formatter** (338 lines) → Extract message type formatters
- Minor method extractions within Application

## 📝 Key Principles

**"You can't just move the problem to a different file"**

✅ **Good refactoring:** Extract classes with clear single responsibilities
❌ **Bad refactoring:** Move methods to modules just to game metrics

**Development Workflow:**
- Always follow TDD (write tests first)
- Run `rake test` after each extraction
- Run `rake lint` to verify metrics improvement
- Commit frequently with clear messages

## Notes

- Always run tests after each fix: `bundle exec rspec`
- Commit frequently with clear messages
- Follow TDD for any new code (see AGENT.md)
- Prioritize readability over just fixing metrics
- **Don't just move code - actually improve the design**
