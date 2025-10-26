# Formatter.rb Migration Guide

## Quick Reference for Continuing Phase 3.5

This guide shows exactly how to convert each remaining Formatter method from OutputBuffer to ConsoleIO.

## Conversion Pattern

### Basic Pattern
```ruby
# BEFORE (OutputBuffer):
buffer = OutputBuffer.new
buffer.add("Hello world")
@output_manager&.flush_buffer(buffer)

# AFTER (ConsoleIO):
@console.puts("Hello world")
```

### Debug Messages
```ruby
# BEFORE:
buffer = OutputBuffer.new
buffer.debug("Debug info")
@output_manager&.flush_buffer(buffer)

# AFTER:
@console.puts("\e[90mDebug info\e[0m") if @debug
```

### Error Messages
```ruby
# BEFORE:
buffer = OutputBuffer.new
buffer.error("Error occurred")
@output_manager&.flush_buffer(buffer)

# AFTER:
@console.puts("\e[31mError occurred\e[0m")
```

### Multiple Lines
```ruby
# BEFORE:
buffer = OutputBuffer.new
buffer.add("Line 1")
buffer.add("Line 2")
buffer.debug("Debug line")
@output_manager&.flush_buffer(buffer)

# AFTER:
@console.puts("Line 1")
@console.puts("Line 2")
@console.puts("\e[90mDebug line\e[0m") if @debug
```

## ANSI Color Codes

- **Normal**: No color code needed
- **Debug** (gray): `\e[90m...\e[0m`
- **Error** (red): `\e[31m...\e[0m`
- **Success** (green): `\e[32m...\e[0m` (if needed)
- **Warning** (yellow): `\e[33m...\e[0m` (if needed)

## Example: Completed Migration

Here's a real example from `display_assistant_message()` that was already completed:

### BEFORE:
```ruby
def display_assistant_message(message)
  # Display any text content (buffer adds leading newline)
  if message['content'] && !message['content'].strip.empty?
    buffer = OutputBuffer.new
    # Buffer.add() now handles normalization automatically
    buffer.add(message['content'])
    @output_manager&.flush_buffer(buffer)
  elsif !message['tool_calls'] && message['tokens_output'] && message['tokens_output'] > 0
    # LLM generated output but content is empty (unusual case - possibly API issue)
    buffer = OutputBuffer.new
    buffer.debug("(LLM returned empty response - this may be an API/model issue)")
    @output_manager&.flush_buffer(buffer)
  end
  # ... rest of method
end
```

### AFTER:
```ruby
def display_assistant_message(message)
  # Display any text content
  if message['content'] && !message['content'].strip.empty?
    @console.puts(message['content'])
  elsif !message['tool_calls'] && message['tokens_output'] && message['tokens_output'] > 0
    # LLM generated output but content is empty (unusual case - possibly API issue)
    @console.puts("\e[90m(LLM returned empty response - this may be an API/model issue)\e[0m") if @debug
  end
  # ... rest of method
end
```

**Key changes**:
1. Removed `buffer = OutputBuffer.new`
2. Replaced `buffer.add(x)` with `@console.puts(x)`
3. Replaced `buffer.debug(x)` with `@console.puts("\e[90m#{x}\e[0m") if @debug`
4. Removed `@output_manager&.flush_buffer(buffer)`

## Methods to Convert (in order of complexity)

### Easy (Simple single-output methods)
1. `display_token_summary()` - Line 94
2. `display_spell_checker_message()` - Line 346

### Medium (Multiple outputs, simple logic)
3. `display_thread_event()` - Line 105
4. `display_system_message()` - Line 309

### Complex (Conditional output, iteration)
5. `display_message_created()` - Line 120
6. `display_llm_request()` - Line 206
7. `display_tool_call()` - Line 357
8. `display_tool_result()` - Line 407
9. `display_error()` - Line 477

## Step-by-Step Process

For each method:

1. **Read the method** - Understand what it outputs
2. **Identify buffer calls**:
   - `buffer.add()` → normal output
   - `buffer.debug()` → debug output with condition
   - `buffer.error()` → error output
3. **Convert one by one**:
   - Replace buffer creation
   - Replace each buffer call with `@console.puts()`
   - Add ANSI codes for debug/error
   - Remove flush_buffer call
4. **Test**: Run `bundle exec rspec spec/nu/agent/application_console_integration_spec.rb`
5. **Commit** (optional but recommended)

## Common Patterns in Formatter

### Pattern 1: Conditional Debug Output
```ruby
# BEFORE:
return unless @debug
buffer = OutputBuffer.new
buffer.debug("[Thread] #{thread_name} #{status}")
@output_manager&.flush_buffer(buffer)

# AFTER:
return unless @debug
@console.puts("\e[90m[Thread] #{thread_name} #{status}\e[0m")
```

### Pattern 2: Verbosity Checks
```ruby
# BEFORE:
verbosity = @application ? @application.verbosity : 0
return if verbosity < 2
buffer = OutputBuffer.new
buffer.debug("Message")
@output_manager&.flush_buffer(buffer)

# AFTER:
verbosity = @application ? @application.verbosity : 0
return if verbosity < 2
@console.puts("\e[90mMessage\e[0m")
```

### Pattern 3: Multiline with Iteration
```ruby
# BEFORE:
buffer = OutputBuffer.new
items.each do |item|
  buffer.add("  - #{item}")
end
@output_manager&.flush_buffer(buffer)

# AFTER:
items.each do |item|
  @console.puts("  - #{item}")
end
```

## Testing After Each Change

```bash
# Quick test - just Application integration
bundle exec rspec spec/nu/agent/application_console_integration_spec.rb

# If that passes, run ConsoleIO tests
bundle exec rspec spec/nu/agent/console_io_spec.rb

# Once all methods converted, run full suite
bundle exec rspec
```

## Troubleshooting

**If tests fail**:
1. Check for missing `if @debug` conditions
2. Verify ANSI color codes are correct
3. Make sure all `@output_manager&.flush_buffer()` calls are removed
4. Check for typos in variable interpolation

**Common mistakes**:
- Forgetting `if @debug` on debug messages
- Using `@output` instead of `@console`
- Not removing the `flush_buffer` line
- Incorrect ANSI escape codes

## When Done

After all 9 methods are converted:
1. Run full test suite
2. Remove legacy code from Application.rb
3. Update Options.rb and lib/nu/agent.rb
4. Delete legacy files
5. Final integration testing

## Questions?

Refer to:
- `PHASE_3.5_PROGRESS.md` - Overall progress
- `plan.md` - Phase 3.5 section for full context
- `spec/nu/agent/application_console_integration_spec.rb` - Tests
- `lib/nu/agent/console_io.rb` - ConsoleIO implementation
