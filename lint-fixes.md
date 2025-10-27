# RuboCop Refactoring Guide

## Current Status (2025-10-26)

- **Total violations:** 25 (down from 97 at session start - **74% reduction**)
- **Tests:** 623 passing ✅

**Remaining violations:**
- Metrics/AbcSize: 13
- Metrics/MethodLength: 11
- Metrics/ClassLength: 1 (Formatter only)

**Files with violations:** 24 files (most have 1 violation each)

---

## Goal

**Eliminate all RuboCop violations while maintaining 100% test coverage.**

Target: 0 violations, 623+ tests passing

---

## Prioritization Strategy

**Focus on maximum impact per effort:**

1. **Files with multiple violations** - Bigger wins per file
   - Application.rb (2 violations)
   - Formatter.rb (1 ClassLength)

2. **Files with 1-2 violations** - Quick wins
   - Tool files (file operations, formatters)
   - Command files
   - Service classes

3. **Auto-correctable violations** - Run `bundle exec rubocop -a` first

**Check current violations:**
```bash
bundle exec rubocop --format offenses
bundle exec rubocop | grep -E "^lib/.*\.rb:" | awk -F: '{print $1}' | sort | uniq -c | sort -rn
```

---

## Refactoring Approach

### TDD Red-Green-Refactor Cycle

**ALWAYS follow Test-Driven Development:**

1. **RED:** Check if tests exist, write new ones if needed
2. **GREEN:** Verify tests pass before refactoring
3. **REFACTOR:** Extract methods/classes while keeping tests green

### Extract Method Pattern

**For AbcSize/MethodLength violations:**

```ruby
# Before: Complex 50-line method
def execute(args)
  # validation logic (10 lines)
  # processing logic (20 lines)
  # formatting logic (15 lines)
  # error handling (5 lines)
end

# After: Clean delegation
def execute(args)
  return error_response unless valid_args?(args)

  data = process_data(args)
  format_response(data)
end

private

def valid_args?(args)
  # validation logic
end

def process_data(args)
  # processing logic
end

def format_response(data)
  # formatting logic
end

def error_response
  # error handling
end
```

### Verification Workflow

After each change:

```bash
# 1. Run specific test file
bundle exec rspec spec/path/to/file_spec.rb --format documentation

# 2. Check violations for that file
bundle exec rubocop lib/path/to/file.rb

# 3. Run all tests (before commit)
bundle exec rspec --format progress

# 4. Commit with descriptive message
git add lib/path/to/file.rb
git commit -m "Refactor ClassName - eliminate X violations (TDD)

- extract_helper_1: Purpose
- extract_helper_2: Purpose

All N tests passing. XX → YY violations (ZZ% total reduction)."
git push
```

---

## Key Principles

**Good Refactoring:**
- ✅ Extract methods with clear single responsibilities
- ✅ Name methods descriptively (what they do, not how)
- ✅ Keep all tests passing throughout
- ✅ Run tests after EVERY change
- ✅ Commit frequently with clear messages

**Bad Refactoring:**
- ❌ Moving code without improving design
- ❌ Skipping tests
- ❌ Breaking existing functionality
- ❌ Creating unclear/cryptic method names

**Common Patterns:**
- Extract parameter validation → `validate_args`, `parse_arguments`
- Extract formatting logic → `format_response`, `build_result_hash`
- Extract business logic → `process_data`, `calculate_result`
- Extract error handling → `error_response`, `handle_error`
- Extract I/O operations → `read_from_source`, `write_to_destination`

---

## Starting a New Session

When starting fresh with limited context:

1. **Read this file** to understand the current state and approach
2. **Check current status:**
   ```bash
   bundle exec rubocop --format offenses
   bundle exec rspec --format progress | tail -3
   ```
3. **Identify target files** (files with most violations)
4. **Pick ONE file** to refactor
5. **Follow the TDD workflow** above
6. **Commit and continue** to next file

**Remember:** You're at 25 violations (74% reduction from start). Focus on files with 2+ violations for maximum impact, then tackle single-violation files.

---

## Quick Reference

**Most useful commands:**
```bash
# Overall status
bundle exec rubocop | grep -E "files inspected|offenses detected"

# Files sorted by violation count
bundle exec rubocop 2>&1 | grep -E "^lib/.*\.rb:" | awk -F: '{print $1}' | sort | uniq -c | sort -rn

# Check specific file
bundle exec rubocop lib/path/to/file.rb

# Run specific test file
bundle exec rspec spec/path/to/file_spec.rb --format documentation

# Run all tests
bundle exec rspec --format progress

# Auto-fix safe violations
bundle exec rubocop -a
```

---

**Progress:** 97 → 25 violations (74% reduction)
**Goal:** 0 violations
**Status:** 25 violations remaining in 24 files
