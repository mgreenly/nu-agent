# Agent Development Guidelines

## Test-Driven Development (TDD)

**ALWAYS follow TDD practices:**

1. **Red Test First** - Write a failing test that defines the desired behavior
2. **Green Test** - Write the minimal code to make the test pass
3. **Refactor** - Improve the code while keeping tests green

Never write implementation code before writing the test that validates it.

## Code Quality Standards

**All new code MUST pass RuboCop linting:**

- Run `bundle exec rubocop` before committing
- Fix all offenses in new/modified code
- Use `bundle exec rubocop -a` for auto-correctable offenses
- Do not introduce new lint violations

## Workflow

1. Write a failing test (Red)
2. Run the test suite to confirm it fails: `bundle exec rspec`
3. Write minimal code to make the test pass (Green)
4. Run the test suite to confirm it passes: `bundle exec rspec`
5. Refactor if needed, keeping tests green
6. Run RuboCop: `bundle exec rubocop`
7. Fix any lint violations
8. Commit changes

---

*This document will be expanded with additional guidelines as the project evolves.*
