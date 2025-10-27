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
- Line length limit: 120 characters (configured in `.rubocop.yml`)

## CODE SMELLS TO AVOID!!!

- Using @ sigils on instance variables when attr_accesor, attr_reader or attr_writer exists.
- Using instance_variable_get to access instance variables outside from outside the instance.

## Code Style Preferences

**Line Length Management:**

When fixing line length violations, follow this priority order:

1. **Use heredocs for long multi-line text** - Especially for help messages, prompts, and descriptions
   ```ruby
   # Good
   help_text = <<~HELP
     This is a long help message that spans
     multiple lines with proper formatting.
   HELP

   # Avoid
   text = "This is a long help message " \
          "that spans multiple lines"
   ```

2. **Shorten variable names in code (not user-facing text)** - Before breaking lines
   ```ruby
   # Good - user sees full message, code is concise
   completed = status["completed"]
   total = status["total"]
   puts "Status: #{completed}/#{total}"

   # Avoid - breaking user-visible text
   puts "Status: compl/tot"
   ```

3. **Never shorten user-facing text** - Only shorten internal identifiers
   - ✓ User messages, help text, error messages → keep full text
   - ✓ Variable names, parameter names → can be shortened
   - ✗ Don't sacrifice clarity for brevity

4. **Break lines as last resort** - After trying other approaches
   ```ruby
   # Acceptable when other options exhausted
   output_line("Very long message text",
               type: :debug)
   ```

**Other Style Guidelines:**

- Use double quotes for strings (enforced by RuboCop)
- Use meaningful but concise variable names
- Extract intermediate variables to improve readability and reduce line length

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
