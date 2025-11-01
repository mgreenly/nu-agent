# Agent Development Guide

## Project Management
- Use GitHub Issues to track enhancement plans and feature requests
- Include NO attribution lines in the commit messages, only the signing committer is relavent.
- Always assume the database is $PWD/db/memory.db

## Plan Execution
- Create `docs/dev/plan-<NAME>.md` with clear phases and tasks
- Use TDD red/green cycles for all changes
- Every task requires passing `rake test`, `rake lint`, and `rake coverage`
- Commit after each completed task
- Update plan document progress after each task
- All plan files must include a final step for manual validation
- Always include the plan file name in work summaries
- Manual test/validation steps in plans are for human verification only

## TDD: Red → Green → Refactor
1. Write failing test first
2. Write minimal code to pass
3. Refactor while keeping tests green

**Never write the implementation before tests.**

## Style & Code Quality
- There are NO acceptable RuboCop violations.
- `rake coverage:enforce` must pass before additions or changes are considered complete.
- Maintain 0.01% positive margin above required coverage threshold.
- ALWAYS run `rake test` and `rake lint` and `rake coverage` before commits.
- ALWAYS use good design when addressing lint or spec issues.  DON'T Cheat!
- Concise but meaningful variable names

## Git Operations
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
- Gap from required thresholds (98.15% line, 90.00% branch)
- Files with lowest coverage, sorted by percentage
- Specific gap for each file

## Code Smells to Avoid
- Using `@` sigils when `attr_accessor/reader/writer` exists
- Using `instance_variable_get` from outside the instance
