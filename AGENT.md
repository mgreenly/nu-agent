# Agent Development Guidelines

## Project Management
- Use GitHub Issues to track enhancement plans and feature requests

## TDD: Red → Green → Refactor
1. Write failing test first
2. Write minimal code to pass
3. Refactor while keeping tests green

**Never write implementation before tests.**

## Code Quality
- All code must pass RuboCop (`bundle exec rubocop -a`), NO exceptions.
- Line length: 120 chars max
- Run tests before committing (`bundle exec rspec`)
- Remove unused parameters don't prefix them with `_` to silence RuboCop

## Line Length Fixes (Priority Order)
1. Use heredocs for long text (help messages, prompts)
2. Shorten variable names (not user-facing text)
3. Never abbreviate user messages
4. Break lines as last resort

## Style
- Double quotes for strings
- Concise but meaningful variable names
- Extract intermediate variables for clarity

## Code Smells to Avoid
- Using `@` sigils when `attr_accessor/reader/writer` exists
- Using `instance_variable_get` from outside the instance
