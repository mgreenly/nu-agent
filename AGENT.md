# Agent Development Guide

## Project Management
- Use GitHub Issues to track enhancement plans and feature requests
- Include NO attribution lines in the commit messages.
- Always assume the database is $PWD/db/memory.db

## When Creating Plans
- Create `docs/dev/plan-<NAME>.md` before starting implementation
- Structure plans with clear phases and numbered tasks
- Each task should be atomic and testable
- Include specific success criteria for each task
- All plan files must include a final step for manual human validation
- Focus on correctness and design of requested features. Do not add speculative or invented features.

## When Executing Plans
- Follow the plan document strictly, task by task
- Use TDD red/green cycles for all changes
- The TDD cycle is not complete until `rake test`, `rake lint`, and `rake coverage` pass.
- After the TDD cycle is complete mark the task complete in the plan.
- Commit after each completed task
- Always include the plan file name, current task and next task, in work summaries

## TDD: Red → Green → Refactor
1. Write failing test first
2. Write minimal code to pass
3. Refactor while keeping tests green

**Never write the implementation before tests.**

## Style & Code Quality
- There are NO acceptable RuboCop violations.
- `rake coverage:enforce` must pass before additions or changes are considered complete.
- **All modified files MUST have 100% line and branch coverage before being committed.**
  - When modifying existing code, ensure all new branches and lines are fully tested.
  - Use `bin/coverage-report` to verify file-level coverage after changes.
- ALWAYS run `rake test` and `rake lint` and `rake coverage` before commits.
- ALWAYS use good design when addressing lint or spec issues.  DON'T Cheat!
- Concise but meaningful variable names

## Git Operations
- **NEVER push unless asked to***
- **NEVER use `git stash`**: Changes must be committed to branches, not stashed
- **During rebasing**: Tests must pass but coverage and lint requirements can be temporarily ignored
- **After rebasing**: Coverage and lint must be brought into full compliance before considering work complete

## Development Tools

### Test Output Configuration
- RSpec is configured with `--format progress` in `.rspec` for concise output
- Only failures show detailed information
- Passing tests show as dots (`.`), failures as `F`, pending as `*`

### Coverage Analysis
To get a detailed coverage report showing files that need more coverage:
```bash
# Run tests with JSON coverage output
COVERAGE_JSON=true bundle exec rspec

# Analyze coverage and show files below 100%
bin/coverage-report
```

The coverage report shows:
- Overall line and branch coverage percentages
- Gap from required thresholds (99.61% line, 91.59% branch)
- Files with lowest coverage, sorted by percentage
- Specific gap for each file

## Code Smells to Avoid
- Using `@` sigils when `attr_accessor/reader/writer` exists
- Using `instance_variable_get` from outside the instance
