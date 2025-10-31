# Agent Development Guide

## Project Management
- Use GitHub Issues to track enhancement plans and feature requests
- Include NO attribution lines in the commit messages, only the signing committer is relavent.
- Always assume the database is $PWD/db/memory.db

## Plan Execution
- Create `docs/plan-<NAME>.md` with clear phases and tasks
- Use TDD red/green cycles for all changes
- Every task requires passing `rake test`, `rake lint`, and `rake coverage`
- Commit after each completed task
- Update plan document progress after each task

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

## Code Smells to Avoid
- Using `@` sigils when `attr_accessor/reader/writer` exists
- Using `instance_variable_get` from outside the instance
