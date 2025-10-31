# Plan: API Error Handling with Fibonacci Backoff Retry

## Overview
Implement resilient API error handling across all LLM clients (Anthropic, OpenAI, Google) to automatically retry transient failures using Fibonacci backoff. This will prevent single network glitches or temporary server issues (like 502 Bad Gateway) from terminating user exchanges.

**Goal**: Make the application resilient to transient API failures while providing clear user feedback during retry attempts.

## Current State Analysis

### What Works
1. **Error Detection**: All clients properly catch `Faraday::Error` exceptions (e.g., `anthropic.rb:64-66`)
2. **Error Recording**: Errors are saved to the database with full context (`tool_call_orchestrator.rb:54-71`)
3. **Graceful Failure**: Exchanges are marked as "failed" and transactions commit properly (`chat_loop_orchestrator.rb:117-127`)
4. **Existing Retry Pattern**: `embedding_generator.rb:226-270` already implements retry with exponential backoff

### What's Missing
1. **No retry logic in main API clients** - transient errors immediately fail the exchange
2. **No user visibility during retries** - users don't know the system is recovering from errors
3. **No interrupt handling during retries** - Ctrl-C can't abort a retry sequence

### Problem Example
```
User prompt: "read docs/plan-parallel-tool-execution.md..."
API Error: 502 Bad Gateway (Cloudflare transient failure)
Exchange ends immediately - no retry attempted
User sees error and must re-submit the entire prompt
```

## Requirements

1. **Fibonacci Backoff**: Use Fibonacci sequence for retry delays: 1, 1, 2, 3, 5 seconds
2. **Unlimited Retries**: Continue retrying forever with 5-second delays until user interrupts
3. **Maximum Delay Cap**: Cap individual retry delay at 5 seconds maximum
4. **Visible Warnings**: Display warning messages (even when debug=off) for waits > 3 seconds
5. **Interrupt Support**: Ctrl-C during retry should fail through to user and end the exchange
6. **Error Classification**: Only retry transient errors (502, 503, 504, 429), not client errors (400, 401, 403)
7. **Consistent Behavior**: Apply same retry logic across all three API clients

## Proposed Solution

### Retry Strategy
- **Unlimited Attempts**: Retry indefinitely until API succeeds or user presses Ctrl-C
- **Fibonacci Delays**: 1s, 2s, 3s, 5s, 5s, 5s... (capped at 5 seconds)
- **Progressive Backoff**: Delays increase following Fibonacci sequence up to 5s max
- **Steady State**: After reaching 5s delay, maintain 5s between all subsequent retries
- **Early Exit**: Stop immediately on non-retryable errors or user interrupt (Ctrl-C)

### Fibonacci Sequence
```
Attempt 1: Immediate (initial request)
Attempt 2: Wait 1s  (Fibonacci[0])
Attempt 3: Wait 2s  (Fibonacci[2])
Attempt 4: Wait 3s  (Fibonacci[3]) ← Warning displayed
Attempt 5: Wait 5s  (Fibonacci[4] capped at 5s) ← Warning displayed
Attempt 6: Wait 5s  (capped at 5s) ← Warning displayed
Attempt 7: Wait 5s  (capped at 5s) ← Warning displayed
Attempt 8: Wait 5s  (capped at 5s) ← Warning displayed
... continues indefinitely until success or Ctrl-C
```

**Note**: Fibonacci would continue as 8, 13, 21, 34... but we cap all delays at 5 seconds for reasonable user experience.

### Warning Messages
For delays > 3 seconds, display to console (visible regardless of debug mode):
```
⚠️  API request failed (502 Bad Gateway), retrying in 5 seconds... (attempt 4)
   Press Ctrl-C to cancel
```

**Color Styling**:
- Warning messages: Unobtrusive yellow (`\e[33m`) - visible but not alarming
- Error messages (final failure): Softer red (`\e[91m`) - less harsh than standard red

## Implementation Details

### 1. Error Classification

**Retryable Errors** (transient):
- **429**: Rate limit exceeded
- **502**: Bad Gateway (proxy/server error)
- **503**: Service Unavailable
- **504**: Gateway Timeout
- **Network errors**: Connection timeout, connection refused

**Non-Retryable Errors** (permanent):
- **400**: Bad Request (invalid parameters)
- **401**: Unauthorized (invalid API key)
- **403**: Forbidden (quota exceeded, permissions)
- **404**: Not Found (invalid endpoint)
- **422**: Unprocessable Entity (invalid request structure)
- **500**: Internal Server Error (server-side bug - unlikely to resolve with retry)

### 2. Fibonacci Backoff Calculator

```ruby
module Nu
  module Agent
    module RetrySupport
      # Calculate Fibonacci delay for given attempt number
      # attempt 1 = 1s, attempt 2 = 2s, attempt 3 = 3s, attempt 4 = 5s, 5s, 5s...
      # Capped at 5 seconds maximum
      def fibonacci_delay(attempt, max_delay: 5)
        return 0 if attempt < 1

        # Fibonacci sequence: 1, 1, 2, 3, 5, 8, 13, 21, 34...
        # For retry attempts: use position in sequence, capped at max_delay
        fib_value = calculate_fibonacci(attempt)
        [fib_value, max_delay].min
      end

      private

      def calculate_fibonacci(n)
        return 1 if n <= 2

        a, b = 1, 1
        (n - 1).times { a, b = b, a + b }
        a
      end
    end
  end
end
```

### 3. Retry Logic with Interrupt Handling

**Recursive Approach** (simple, clean code):
```ruby
def send_message_with_retry(messages:, system_prompt:, tools:, attempt: 1)
  begin
    # Make API call
    response = @client.messages(parameters: parameters)
    return parse_response(response)
  rescue Faraday::Error => e
    # Check if error is retryable
    return format_error_response(e) unless retryable_error?(e)

    # Calculate delay and display warning if needed
    delay = fibonacci_delay(attempt)
    display_retry_warning(e, delay, attempt) if delay > 3

    # Sleep with interrupt check
    interruptible_sleep(delay)

    # Retry indefinitely until success or Ctrl-C
    send_message_with_retry(messages: messages, system_prompt: system_prompt,
                           tools: tools, attempt: attempt + 1)
  end
rescue Interrupt
  # Ctrl-C pressed - convert to retryable error and let it fail
  raise # Re-raise so it propagates up to exchange handler
end
```

**Iterative Approach** (alternative if stack depth becomes an issue):
```ruby
def send_message_with_retry(messages:, system_prompt:, tools:)
  attempt = 1

  loop do
    begin
      # Make API call
      response = @client.messages(parameters: parameters)
      return parse_response(response)
    rescue Faraday::Error => e
      # Check if error is retryable
      return format_error_response(e) unless retryable_error?(e)

      # Calculate delay and display warning if needed
      delay = fibonacci_delay(attempt)
      display_retry_warning(e, delay, attempt) if delay > 3

      # Sleep with interrupt check
      interruptible_sleep(delay)

      # Increment attempt counter and continue loop
      attempt += 1
    rescue Interrupt
      # Ctrl-C pressed - re-raise to propagate
      raise
    end
  end
end
```

**Recommendation**: Start with **iterative approach** for production reliability. While recursive is cleaner, iterative avoids any possibility of stack overflow during extended outages.

Ruby stack depth limit is typically ~10,000 frames. With 5-second delays, reaching this would take:
- 10,000 attempts × 5 seconds = 50,000 seconds = ~14 hours

While unlikely, the iterative approach eliminates this risk entirely with no downsides.

def interruptible_sleep(duration)
  # Sleep in small increments, checking for interrupts
  # This allows Ctrl-C to work during long sleeps
  end_time = Time.now + duration

  while Time.now < end_time
    sleep(0.1)
    # Ruby will raise Interrupt if Ctrl-C is pressed
  end
rescue Interrupt
  # Ctrl-C during retry - re-raise to abort exchange
  raise
end

def retryable_error?(error)
  status = error.response&.dig(:status)

  # HTTP status codes that indicate transient failures
  transient_statuses = [429, 502, 503, 504]

  # Network-level errors (no HTTP status)
  return true if status.nil? && network_error?(error)

  transient_statuses.include?(status)
end

def network_error?(error)
  # Faraday::ConnectionFailed, Faraday::TimeoutError, etc.
  error.is_a?(Faraday::ConnectionFailed) ||
  error.is_a?(Faraday::TimeoutError) ||
  error.message.match?(/connection|timeout|network/i)
end

def display_retry_warning(error, delay, attempt)
  status = error.response&.dig(:status) || "Network Error"
  message = error.message.split("\n").first || "Unknown error"

  # Display warning in unobtrusive yellow (visible even when debug is off)
  warning_msg = "\e[33m⚠️  API request failed (#{status}: #{message}), retrying in #{delay} seconds... (attempt #{attempt})\e[0m"
  cancel_msg = "\e[33m   Press Ctrl-C to cancel\e[0m"

  # Use console.puts directly to bypass output_line type filtering
  @application&.console&.puts(warning_msg)
  @application&.console&.puts(cancel_msg)
end
```

### 4. Configuration Support

Add configuration keys to database config table:
- `api_retry_max_delay` (default: 5) - Maximum individual retry delay in seconds
- `api_retry_show_warnings` (default: true) - Show retry warnings for delays > 3 seconds

**Note**: Max attempts is not configurable - retries continue indefinitely until success or Ctrl-C.

## Code Changes Required

### File: `lib/nu/agent/retry_support.rb` (NEW)
Create shared module with:
- `fibonacci_delay(attempt, max_delay:)` - Calculate Fibonacci backoff
- `retryable_error?(error)` - Classify errors as retryable/non-retryable
- `network_error?(error)` - Detect network-level failures
- `interruptible_sleep(duration)` - Sleep with Ctrl-C support
- `display_retry_warning(error, delay, attempt, max_attempts)` - User feedback

### File: `lib/nu/agent/clients/anthropic.rb`
**Current** (lines 58-69):
```ruby
def send_message(messages:, system_prompt: SYSTEM_PROMPT, tools: nil)
  formatted_messages = format_messages(messages)
  parameters = build_request_parameters(formatted_messages, system_prompt, tools)

  begin
    response = @client.messages(parameters: parameters)
  rescue Faraday::Error => e
    return format_error_response(e)
  end

  parse_response(response)
end
```

**Modified**:
```ruby
def send_message(messages:, system_prompt: SYSTEM_PROMPT, tools: nil)
  formatted_messages = format_messages(messages)
  parameters = build_request_parameters(formatted_messages, system_prompt, tools)
  attempt = 1

  loop do
    begin
      response = @client.messages(parameters: parameters)
      return parse_response(response)
    rescue Faraday::Error => e
      # Non-retryable errors fail immediately
      return format_error_response(e) unless retryable_error?(e)

      # Retryable errors: calculate delay and display warning
      delay = fibonacci_delay(attempt)
      display_retry_warning(e, delay, attempt) if delay > 3

      # Sleep with interrupt support
      interruptible_sleep(delay)

      # Increment attempt and continue loop
      attempt += 1
    rescue Interrupt
      raise # Let Ctrl-C propagate to exchange handler
    end
  end
end

private

# Include RetrySupport methods: fibonacci_delay, retryable_error?, etc.
include RetrySupport
```

### File: `lib/nu/agent/clients/openai.rb`
Apply same pattern as Anthropic client above.

### File: `lib/nu/agent/clients/google.rb`
Apply same pattern as Anthropic client above.

### File: `lib/nu/agent/clients/openai_embeddings.rb`
**Consider**: The embedding worker already has retry logic (`embedding_generator.rb:226-270`). We could:
1. Keep existing embedding retry logic (it uses exponential backoff)
2. Refactor to use new RetrySupport module with Fibonacci backoff
3. Leave as-is since embeddings are background tasks with different requirements

**Recommendation**: Leave embedding worker as-is (exponential backoff is fine for background tasks). The RetrySupport module is for interactive user-facing API calls where predictable, shorter delays are preferred.

### File: `lib/nu/agent/application.rb`
**Update** (line 68):
Change error color from harsh red to softer red:

**Current**:
```ruby
when :error
  @console.puts("\e[31m#{text}\e[0m")
```

**Modified**:
```ruby
when :error
  @console.puts("\e[91m#{text}\e[0m")  # Softer red (bright red is actually lighter)
```

## Testing Strategy

### Unit Tests

1. **Retry Logic Tests** (`spec/nu/agent/retry_support_spec.rb`):
   - Fibonacci delay calculation for attempts 1-10
   - Max delay capping at 5 seconds (verify attempts 5+ all return 5s)
   - Error classification (retryable vs non-retryable)
   - Network error detection

2. **Client Tests** (update existing specs):
   - `anthropic_spec.rb`, `openai_spec.rb`, `google_spec.rb`
   - Mock transient errors (502, 503, 504, 429)
   - Verify retry attempts with correct Fibonacci delays (1s, 2s, 3s, 5s)
   - Verify delays cap at 5 seconds for attempts 5+
   - Verify non-retryable errors fail immediately (400, 401, 403)
   - Mock Interrupt exception during retry to test Ctrl-C handling
   - Verify retries continue indefinitely until success (test up to 10 attempts)

### Integration Tests

1. **Simulated Network Failures**:
   - Use WebMock to simulate 502 error on first attempt, success on second
   - Verify exchange completes successfully after retry

2. **Rate Limiting**:
   - Simulate 429 (rate limit) errors
   - Verify Fibonacci backoff is applied

3. **User Interrupt**:
   - Simulate Interrupt during retry sleep
   - Verify exchange fails gracefully without retry completion

### Manual Testing

1. **Network Disconnect Test**:
   - Temporarily disable network during API call
   - Verify retry warnings appear
   - Re-enable network and verify recovery

2. **Ctrl-C During Retry**:
   - Trigger 502 error (can use network proxy)
   - Press Ctrl-C during retry countdown
   - Verify exchange ends immediately

## Edge Cases and Considerations

### 1. Nested Tool Calls with Retries
**Scenario**: LLM makes multiple tool calls, one triggers an API call that fails and retries.

**Consideration**: Retry logic is at the API client level, so tool execution just waits for the retry to complete. This is correct behavior - from the tool's perspective, it's a single (slow) API call.

### 2. Infinite Retry Sequences
**Scenario**: Retries continue indefinitely with 5-second delays. A long outage could result in many retry attempts.

**Consideration**: Users might find this frustrating during extended outages. Mitigations:
1. Warning messages make it clear what's happening and show attempt count
2. Ctrl-C provides immediate escape hatch
3. 5-second delay is short enough to be tolerable but long enough to avoid hammering APIs
4. Users can see progress and make informed decision to cancel or wait

### 3. Parallel Tool Execution (Future)
**Scenario**: When implementing parallel tool execution (from `plan-parallel-tool-execution.md`), multiple API calls might retry simultaneously.

**Consideration**:
- Each thread handles its own retries independently
- ConsoleIO's thread-safe queue ensures warning messages don't interleave
- Interrupt handling works per-thread (Ruby raises Interrupt in all threads)

### 4. Database Transactions During Retry
**Scenario**: Exchange transaction is open while API call retries.

**Consideration**: This is fine - the transaction encompasses the entire exchange execution. If retries succeed, exchange completes normally. If all retries fail, transaction rolls back (per `chat_loop_orchestrator.rb:21-24`).

### 5. Background Worker Coordination
**Scenario**: Background workers might try to process data while main thread is retrying.

**Consideration**: Workers already use mutexes for critical sections (`application.rb:190-206`). Retry logic doesn't introduce new concurrency issues.

### 6. Quota/Rate Limit Exhaustion
**Scenario**: 429 errors might persist indefinitely if quota is exhausted for the billing period.

**Consideration**:
- Fibonacci backoff gives API time to reset rate limits (for rolling windows)
- If quota is truly exhausted for the billing period, retries will continue until user cancels
- User must press Ctrl-C to abort when they realize quota is depleted
- Future enhancement: Detect repeated 429 errors and suggest checking quota status

## Future Enhancements

1. **Adaptive Retry**: Learn from error patterns and adjust retry strategy
   - Track success rate per status code
   - Increase delays for frequently failing endpoints

2. **Circuit Breaker**: Temporarily disable retries if API is consistently failing
   - Prevents wasting time on dead endpoints
   - Auto-fail with clear message: "API unavailable (circuit breaker triggered)"
   - Resume retries after cooldown period

3. **Retry Metrics**: Track and display retry statistics
   - Number of retries per session
   - Success rate after retry
   - Average retry duration
   - Display in `/info` command

4. **Provider-Specific Strategies**: Different backoff for different providers
   - Anthropic might have different rate limits than OpenAI
   - Configure per-provider retry policies
   - Different max delays per provider

5. **Progressive Warning Escalation**: Change message tone as retries continue
   - Attempts 1-10: Normal yellow warnings
   - Attempts 11-30: Add hint about potential extended outage
   - Attempts 31+: Suggest checking API status page

## Implementation Checklist

### Phase 1: Core Retry Logic
- [ ] Create `lib/nu/agent/retry_support.rb` module
- [ ] Implement `fibonacci_delay` calculation
- [ ] Implement `retryable_error?` classification
- [ ] Implement `network_error?` detection
- [ ] Implement `interruptible_sleep` with Interrupt handling
- [ ] Implement `display_retry_warning` with ConsoleIO integration
- [ ] Write unit tests for RetrySupport module (20+ test cases)

### Phase 2: Client Integration
- [ ] Update `anthropic.rb` to use RetrySupport
- [ ] Update `openai.rb` to use RetrySupport
- [ ] Update `google.rb` to use RetrySupport
- [ ] Update `application.rb` error color to softer red (\e[91m)
- [ ] Update client specs with retry test cases
- [ ] Manual testing with simulated network failures

### Phase 3: Configuration (Optional)
- [ ] Add database config keys for retry settings (`api_retry_max_delay`, `api_retry_show_warnings`)
- [ ] Update clients to load max_delay from database config
- [ ] Document retry behavior in help system

### Phase 4: Polish
- [ ] Add retry metrics to `/info` command output
- [ ] Update CHANGELOG.md with enhancement details
- [ ] Update README.md with retry behavior documentation
- [ ] Integration testing with real API failures

## Success Criteria

1. **Resilience**: Transient 502/503/504 errors automatically recover without user intervention
2. **Persistence**: Retries continue indefinitely until API recovers or user cancels
3. **Visibility**: Users see clear warnings during retry sequences (for delays > 3s)
4. **Control**: Ctrl-C during retry immediately fails the exchange
5. **Consistency**: All three API clients behave identically for retries
6. **Responsiveness**: Maximum 5-second delay between retry attempts
7. **Test Coverage**: >95% line coverage for RetrySupport module

## Risk Assessment

**Low Risk**:
- Self-contained change (new module + client modifications)
- Existing error handling remains functional (additive change)
- Interrupt handling uses existing Ruby mechanisms
- Max delay capped at 5 seconds (reasonable user experience)

**Medium Risk**:
- Infinite retries during extended outages could frustrate users → Mitigated by clear warnings showing attempt count and Ctrl-C escape
- Users might not realize they can press Ctrl-C → Warning message explicitly instructs to "Press Ctrl-C to cancel"
- User might accidentally leave terminal running during multi-hour outage → Iterative implementation prevents stack issues; API calls eventually succeed or user returns to cancel

**High Risk**:
- None identified

## References

- Existing retry implementation: `lib/nu/agent/workers/embedding_generator.rb:226-270`
- Error handling: `lib/nu/agent/clients/anthropic.rb:150-170`
- Exchange orchestration: `lib/nu/agent/chat_loop_orchestrator.rb:15-49`
- Interrupt handling: `lib/nu/agent/application.rb:214-218`
- Parallel tool execution plan: `docs/plan-parallel-tool-execution.md`

---

**Document Version**: 1.0
**Created**: 2025-10-30
**Status**: Ready for Implementation
