# Plan: Remove Spell Checker (Issue #29)

## Overview
Remove the spell checker functionality from nu-agent, including:
- Core spell checker implementation
- User-facing commands (`/spellcheck`)
- Configuration and model management
- Debug subsystem for spellcheck
- All related tests and documentation references

## Approach
Use TDD red/green cycles with incremental removal, ensuring tests/lint/coverage pass at each gateway checkpoint.

## 🔄 IMPORTANT: Progress Tracking

**After EVERY cycle (Red/Green/Gateway), update this plan document:**

1. Check off completed checkboxes: `- [ ]` → `- [x]`
2. Add notes about any issues or deviations encountered
3. Commit the updated plan with: `git add docs/dev/plan-issue-29-remove-spellcheck.md`
4. This creates a clear audit trail and helps track progress

**Example:**
```markdown
- [x] **Green:** Run `bundle exec rspec` - all tests should pass
  - Note: Had to also update chat_loop_orchestrator_spec.rb to remove spell_check mock
```

Do NOT proceed to the next phase until the current phase is complete and documented!

---

## Phase 1: Remove User-Facing Commands

### 1.1 Remove `/spellcheck` command
**TDD Approach:** Tests should fail when command is removed

- [x] **Red:** Run tests - `spellcheck_command_spec.rb` should pass
- [x] Remove `lib/nu/agent/commands/spellcheck_command.rb`
- [x] Remove require in `lib/nu/agent.rb` (line 66)
- [x] **Red:** Run `bundle exec rspec spec/nu/agent/commands/spellcheck_command_spec.rb` - should fail (file missing)
- [x] Remove `spec/nu/agent/commands/spellcheck_command_spec.rb`
- [x] Remove command registration in `lib/nu/agent/application.rb` (line 200)
- [x] **Green:** Run `bundle exec rspec` - all tests should pass (2501 examples, 0 failures)
- [x] **Gateway:** Run `bundle exec rubocop` - should pass (276 files, no offenses)
- [x] **Gateway:** Check coverage - 99.46% line coverage, 91.3% branch coverage

### 1.2 Remove `/debug spellcheck` debug command
**TDD Approach:** Tests should fail when command is removed

- [x] **Red:** Run tests - `spellcheck_debug_command_spec.rb` should pass (2 examples, 0 failures)
- [x] Remove `lib/nu/agent/commands/subsystems/spellcheck_debug_command.rb`
- [x] Remove require in `lib/nu/agent.rb` (line 81)
- [x] **Red:** Run `bundle exec rspec spec/nu/agent/commands/subsystems/spellcheck_debug_command_spec.rb` - should fail
- [x] Remove `spec/nu/agent/commands/subsystems/spellcheck_debug_command_spec.rb`
- [x] Remove command registration in `lib/nu/agent/application.rb` (line 209)
- [x] **Green:** Run `bundle exec rspec` - all tests should pass (2499 examples, 0 failures)
- [x] **Gateway:** Run `bundle exec rubocop` - should pass (274 files, no offenses)

**✅ Phase 1 Complete - Update this plan document and commit progress before proceeding!**

---

## Phase 2: Remove Core Spell Checker Implementation

### 2.1 Remove SpellChecker class
**TDD Approach:** Tests should fail, then remove usage, then remove class

- [ ] **Red:** Run `bundle exec rspec spec/nu/agent/spell_checker_spec.rb` - should pass
- [ ] Remove spell checker invocation in `lib/nu/agent/chat_loop_orchestrator.rb` (lines 236-246)
  - Remove the entire `if application.spell_check_enabled && application.spellchecker` block
- [ ] **Red:** Run tests - spell_checker_spec should still pass but integration may have issues
- [ ] Remove `lib/nu/agent/spell_checker.rb`
- [ ] Remove require in `lib/nu/agent.rb` (line 33)
- [ ] **Red:** Run `bundle exec rspec spec/nu/agent/spell_checker_spec.rb` - should fail (file missing)
- [ ] Remove `spec/nu/agent/spell_checker_spec.rb`
- [ ] **Green:** Run `bundle exec rspec` - all tests should pass
- [ ] **Gateway:** Run `bundle exec rubocop` - should pass

### 2.2 Remove spell checker from Application
**TDD Approach:** Update tests first, then remove code

- [ ] Remove `:spellchecker` and `:spell_check_enabled` from `attr_accessor` in `lib/nu/agent/application.rb` (lines 6-7)
- [ ] Search for `@spellchecker` and `@spell_check_enabled` in Application and remove all references
- [ ] Search for `spell_check_enabled` in `application_spec.rb` and update/remove related tests
- [ ] **Red:** Run `bundle exec rspec spec/nu/agent/application_spec.rb` - may fail
- [ ] Fix any failing tests
- [ ] **Green:** Run `bundle exec rspec spec/nu/agent/application_spec.rb` - should pass
- [ ] **Gateway:** Run `bundle exec rspec` - all tests should pass
- [ ] **Gateway:** Run `bundle exec rubocop` - should pass

**✅ Phase 2 Complete - Update this plan document and commit progress before proceeding!**

---

## Phase 3: Remove Configuration and Integration Points

### 3.1 Remove from ConfigurationLoader
**TDD Approach:** Update tests, then remove config loading

- [ ] Remove `:spellchecker` from ModelConfig struct in `lib/nu/agent/configuration_loader.rb` (line 10)
- [ ] Remove all spellchecker model loading logic (lines 35, 42, 48, 53, 62, 73)
- [ ] Remove spellchecker from ApplicationContext (line 95)
- [ ] **Red:** Run `bundle exec rspec spec/nu/agent/configuration_loader_spec.rb` - may fail
- [ ] Update `configuration_loader_spec.rb` to remove spellchecker expectations
- [ ] **Green:** Run `bundle exec rspec spec/nu/agent/configuration_loader_spec.rb` - should pass
- [ ] **Gateway:** Run `bundle exec rspec` - all tests should pass

### 3.2 Remove from SessionInfo
**TDD Approach:** Update tests, then remove display logic

- [ ] Remove spellchecker display from `lib/nu/agent/session_info.rb` (line 30, line 82)
- [ ] **Red:** Run `bundle exec rspec spec/nu/agent/session_info_spec.rb` - may fail
- [ ] Update `session_info_spec.rb` to remove spellchecker expectations
- [ ] **Green:** Run `bundle exec rspec spec/nu/agent/session_info_spec.rb` - should pass
- [ ] **Gateway:** Run `bundle exec rspec` - all tests should pass

### 3.3 Remove from Formatter
**TDD Approach:** Update tests, then remove formatting logic

- [ ] Remove spell_checker message handling in `lib/nu/agent/formatter.rb` (lines 132-134)
- [ ] Remove `display_spell_checker_message` method (around line 318)
- [ ] **Red:** Run `bundle exec rspec spec/nu/agent/formatter_spec.rb` - may fail
- [ ] Update `formatter_spec.rb` to remove spell_checker message expectations
- [ ] **Green:** Run `bundle exec rspec spec/nu/agent/formatter_spec.rb` - should pass
- [ ] **Gateway:** Run `bundle exec rspec` - all tests should pass

### 3.4 Clean up History references
**TDD Approach:** Remove comments and verify tests still pass

- [ ] Remove spell_checker comments in `lib/nu/agent/history.rb` (lines 163, 174)
- [ ] **Green:** Run `bundle exec rspec spec/nu/agent/history_spec.rb` - should still pass (just comments)
- [ ] **Gateway:** Run `bundle exec rspec` - all tests should pass

### 3.5 Clean up ExchangeMigrator references
**TDD Approach:** Remove spell_checker filtering logic

- [ ] Remove spell_checker exclusion in `lib/nu/agent/exchange_migrator.rb` (line 51-52 comment, may affect line 52 logic)
- [ ] Review if the condition `msg["actor"] != "spell_checker"` needs removal or just the comment
- [ ] **Red:** Run `bundle exec rspec spec/nu/agent/exchange_migrator_spec.rb` - should pass before changes
- [ ] Make changes
- [ ] **Green:** Run `bundle exec rspec spec/nu/agent/exchange_migrator_spec.rb` - should still pass
- [ ] **Gateway:** Run `bundle exec rspec` - all tests should pass

### 3.6 Remove from HelpTextBuilder
**TDD Approach:** Update tests, then remove help text

- [ ] Search for spellcheck references in `lib/nu/agent/help_text_builder.rb`
- [ ] Remove `/spellcheck` command from help text
- [ ] **Red:** Run `bundle exec rspec spec/nu/agent/help_text_builder_spec.rb` - may fail
- [ ] Update `help_text_builder_spec.rb` to remove spellcheck expectations
- [ ] **Green:** Run `bundle exec rspec spec/nu/agent/help_text_builder_spec.rb` - should pass
- [ ] **Gateway:** Run `bundle exec rspec` - all tests should pass

**✅ Phase 3 Complete - Update this plan document and commit progress before proceeding!**

---

## Phase 4: Remove Lingering Test References

### 4.1 Search and clean up test references
**TDD Approach:** Identify all test references and clean them up

- [ ] Run: `grep -r "spell" spec/ --include="*.rb" -n`
- [ ] Review each file with spell checker references:
  - [ ] `spec/nu/agent/chat_loop_orchestrator_spec.rb`
  - [ ] `spec/nu/agent/application_console_integration_spec.rb`
  - [ ] Any other specs found
- [ ] Remove or update tests that reference spell checker functionality
- [ ] **Green:** Run `bundle exec rspec` - all tests should pass
- [ ] **Gateway:** Run `bundle exec rubocop` - should pass
- [ ] **Gateway:** Check coverage - should maintain or improve coverage

**✅ Phase 4 Complete - Update this plan document and commit progress before proceeding!**

---

## Phase 5: Database Cleanup (Optional)

### 5.1 Consider database migration for config cleanup
**Note:** This is optional - old config values won't hurt anything

- [ ] Consider if we need to remove `model_spellchecker` and `spell_check_enabled` from config table
- [ ] If yes, create a database migration
- [ ] Test migration on a copy of a real database
- [ ] Document migration in CHANGELOG.md

**✅ Phase 5 Complete (or Skipped) - Update this plan document and commit progress before proceeding!**

---

## Phase 6: Documentation Cleanup

### 6.1 Update documentation
- [ ] Search for "spell" in `docs/` folder: `grep -r "spell" docs/ -i`
- [ ] Update any documentation mentioning spell checker
- [ ] Update CHANGELOG.md with removal note
- [ ] Search README.md for spell checker mentions

**✅ Phase 6 Complete - Update this plan document and commit progress before proceeding!**

---

## Phase 7: Manual Testing

### 7.1 Full application test
- [ ] Build and run the application: `bundle exec ruby -Ilib bin/nu-agent`
- [ ] Verify application starts successfully
- [ ] Test that `/help` command doesn't show `/spellcheck`
- [ ] Test that `/debug` command doesn't show spellcheck subsystem
- [ ] Test basic conversation flow works without spell checking
- [ ] Test `/info` command doesn't show spellchecker model
- [ ] Test that typing `/spellcheck` results in unknown command error
- [ ] Test various commands to ensure no spell checker code is triggered
- [ ] Exit gracefully

### 7.2 Test with existing database
- [ ] Run with an existing conversation database that has spell_checker history
- [ ] Verify no errors occur when reading old messages
- [ ] Verify conversation history displays correctly
- [ ] Verify `/migrate-exchanges` works if spell_checker messages exist

**✅ Phase 7 Complete - Update this plan document and commit progress before proceeding to Final Gateways!**

---

## Final Gateways

- [ ] **Run full test suite:** `bundle exec rspec`
- [ ] **Run linter:** `bundle exec rubocop`
- [ ] **Check coverage:** `bundle exec rspec --format documentation`
- [ ] **Run application manually** and verify no errors
- [ ] **Search for lingering references:** `grep -r "spell" lib/ spec/ --include="*.rb" | grep -v "# spell" | grep -v ".spell"`

**✅ Final Gateways Complete - Update this plan document with final status!**

---

## Completion Checklist

- [ ] All spell checker code removed
- [ ] All spell checker tests removed
- [ ] All integration points cleaned up
- [ ] All tests passing
- [ ] Linter passing
- [ ] Coverage maintained or improved
- [ ] Manual testing completed successfully
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] Ready for commit and PR

---

## Notes

- The `.bak` file (`application.rb.bak`) contains old spell checker code but can be ignored
- Focus on removing from active codebase only
- Keep removal incremental with test gateways
- If any step causes unexpected failures, pause and investigate before proceeding
- Database config values (`model_spellchecker`, `spell_check_enabled`) can remain in database without causing issues
