# LLM Request Builder Refactoring Plan

## Executive Summary

Refactor the LLM request preparation process to use a builder pattern with an internal message format that's LLM-agnostic. This will eliminate duplication, provide consistent debug output, and cleanly separate orchestration from API-specific formatting.

## Current Problems

1. **Duplication**: Tool names appear in both the message content ("Available Tools" section) and as a separate tools parameter
2. **Inconsistent Debug Output**: Different clients have different message structures, making debugging difficult
3. **Tight Coupling**: Orchestration logic is mixed with message formatting
4. **Limited Visibility**: Current debug output uses text preview with character limits instead of showing structure

## Proposed Solution

### 1. Internal Message Format

Create a standardized internal format that all LLMs will use:

```ruby
{
  system_prompt: String,        # System instructions with date placeholder
  messages: Array[Hash],        # Chat history + final user message
  tools: Array[Hash],          # Tool definitions with schemas
  model: String,               # Model identifier
  max_tokens: Integer,         # Max response tokens
  metadata: {                  # Additional context for debugging
    rag_content: Hash,         # RAG components separately
    user_query: String,        # Original user query
    conversation_id: Integer,
    exchange_id: Integer
  }
}
```

### 2. Builder Pattern Implementation

Create `lib/nu/agent/llm_request_builder.rb`:

```ruby
class LlmRequestBuilder
  def with_system_prompt(prompt)
  def with_history(messages)
  def with_rag_content(content)
  def with_user_query(query)
  def with_tools(tool_registry)
  def with_metadata(metadata)
  def build() -> internal_format
end
```

### 3. Debug Output with Verbosity Levels

Replace current text preview with YAML output filtered by verbosity:

| Verbosity | Content Displayed | Description |
|-----------|------------------|-------------|
| 0 | Nothing | No debug output |
| 1 | Final user message | Show only the current user's message |
| 2 | + system_prompt | Add system instructions |
| 3 | + rag_content | Add RAG context (redactions, spell check) |
| 4 | + tools | Add tool definitions and schemas |
| 5 | + full history | Add complete chat history |

**Key Point**: The internal message sent to the LLM is always complete. Verbosity only controls which keys are displayed in debug output.

### 4. Client Translation

Each client translates from internal format to their API format:

#### Anthropic
```ruby
def send_message(internal_request)
  {
    model: @model,
    system: internal_request[:system_prompt],
    messages: internal_request[:messages],
    max_tokens: internal_request[:max_tokens],
    tools: format_tools_for_anthropic(internal_request[:tools])
  }.compact  # Remove nil/empty values if API doesn't support
end
```

#### OpenAI/XAI
```ruby
def send_message(internal_request)
  messages = prepend_system_message(
    internal_request[:system_prompt],
    internal_request[:messages]
  )
  {
    model: @model,
    messages: messages,
    tools: format_tools_for_openai(internal_request[:tools])
  }.compact
end
```

## Implementation Steps

**IMPORTANT: Follow TDD Red → Green → Refactor cycle for EVERY change:**
1. Write failing test first (RED)
2. Write minimal code to pass (GREEN)
3. Refactor while keeping tests green
4. Run `rake test && rake lint && rake coverage` - ALL must pass
5. Commit the change
6. Update this plan document to mark task complete

### Phase 1: Create Builder [2-3 hours]

**Task 1.1: Create `llm_request_builder.rb` with basic structure** ✓ COMPLETE
   - RED: Write test for basic builder initialization ✓
   - GREEN: Implement minimal builder class ✓
   - REFACTOR: Clean up as needed ✓
   - RUN: `rake test && rake lint && rake coverage` ✓
   - COMMIT: "Add LlmRequestBuilder skeleton" ✓
   - UPDATE: Mark task 1.1 complete in plan ✓

**Task 1.2: Implement `with_system_prompt` method** ✓ COMPLETE
   - RED: Write test for system prompt setting ✓
   - GREEN: Implement method ✓
   - REFACTOR: Clean up as needed ✓
   - RUN: `rake test && rake lint && rake coverage` ✓
   - COMMIT: "Add with_system_prompt to LlmRequestBuilder" ✓
   - UPDATE: Mark task 1.2 complete in plan ✓

**Task 1.3: Implement `with_history` method** ✓ COMPLETE
   - RED: Write test for history setting ✓
   - GREEN: Implement method ✓
   - REFACTOR: Clean up as needed ✓
   - RUN: `rake test && rake lint && rake coverage` ✓
   - COMMIT: "Add with_history to LlmRequestBuilder" ✓
   - UPDATE: Mark task 1.3 complete in plan ✓

**Task 1.4: Implement `with_rag_content` method** ✓ COMPLETE
   - RED: Write test for RAG content setting ✓
   - GREEN: Implement method ✓
   - REFACTOR: Clean up as needed ✓
   - RUN: `rake test && rake lint && rake coverage` ✓
   - COMMIT: "Add with_rag_content to LlmRequestBuilder" ✓
   - UPDATE: Mark task 1.4 complete in plan ✓

**Task 1.5: Implement `with_user_query` method** ✓ COMPLETE
   - RED: Write test for user query setting ✓
   - GREEN: Implement method ✓
   - REFACTOR: Clean up as needed ✓
   - RUN: `rake test && rake lint && rake coverage` ✓
   - COMMIT: "Add with_user_query to LlmRequestBuilder" ✓
   - UPDATE: Mark task 1.5 complete in plan ✓

**Task 1.6: Implement `with_tools` method** ✓ COMPLETE
   - RED: Write test for tools setting ✓
   - GREEN: Implement method ✓
   - REFACTOR: Clean up as needed ✓
   - RUN: `rake test && rake lint && rake coverage` ✓
   - COMMIT: "Add with_tools to LlmRequestBuilder" ✓
   - UPDATE: Mark task 1.6 complete in plan ✓

**Task 1.7: Implement `with_metadata` method** ✓ COMPLETE
   - RED: Write test for metadata setting ✓
   - GREEN: Implement method ✓
   - REFACTOR: Clean up as needed ✓
   - RUN: `rake test && rake lint && rake coverage` ✓
   - COMMIT: "Add with_metadata to LlmRequestBuilder" ✓
   - UPDATE: Mark task 1.7 complete in plan ✓

**Task 1.8: Implement `build` method with validation** ✓ COMPLETE
   - RED: Write tests for build process and validation errors ✓
   - GREEN: Implement build method with required field validation ✓
   - REFACTOR: Clean up as needed ✓
   - RUN: `rake test && rake lint && rake coverage` ✓
   - COMMIT: "Add build method with validation to LlmRequestBuilder" ✓
   - UPDATE: Mark task 1.8 complete in plan ✓

### Phase 2: Update Orchestrator [2-3 hours]

**Task 2.1: Integrate builder into `prepare_llm_request`** ✓ COMPLETE
   - RED: Write test for orchestrator using builder ✓
   - GREEN: Update `prepare_llm_request` to use `LlmRequestBuilder` ✓
   - REFACTOR: Clean up as needed ✓
   - RUN: `rake test && rake lint && rake coverage` ✓
   - COMMIT: "Integrate LlmRequestBuilder into orchestrator" ✓
   - UPDATE: Mark task 2.1 complete in plan ✓

**Task 2.2: Remove "Available Tools" section from message content** ✓ COMPLETE
   - RED: Update tests to expect no "Available Tools" in message content ✓
   - GREEN: Remove "Available Tools" section generation (lines ~217-219) ✓
   - REFACTOR: Clean up as needed ✓
   - RUN: `rake test && rake lint && rake coverage` ✓
   - COMMIT: "Remove duplicate Available Tools section from messages" ✓
   - UPDATE: Mark task 2.2 complete in plan ✓

**Task 2.3: Update orchestrator to pass internal format to clients** ✓ COMPLETE
   - RED: Update tests to verify internal format passed to clients ✓
   - GREEN: Modify client calls to pass internal format ✓
   - REFACTOR: Clean up as needed ✓
   - RUN: `rake test && rake lint && rake coverage` ✓
   - COMMIT: "Update orchestrator to pass internal format to clients" ✓
   - UPDATE: Mark task 2.3 complete in plan ✓

### Phase 3: Update Debug Display [2-3 hours]

**Task 3.1: Create YAML formatter with verbosity level 0 (nothing)**
   - RED: Write test for verbosity level 0
   - GREEN: Create basic `llm_request_formatter.rb` with level 0 support
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Add LlmRequestFormatter with verbosity level 0"
   - UPDATE: Mark task 3.1 complete in plan

**Task 3.2: Add verbosity level 1 (final user message)**
   - RED: Write test for verbosity level 1
   - GREEN: Implement YAML output for final user message
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Add verbosity level 1 to formatter"
   - UPDATE: Mark task 3.2 complete in plan

**Task 3.3: Add verbosity levels 2-5**
   - RED: Write tests for levels 2 (+ system), 3 (+ rag), 4 (+ tools), 5 (+ history)
   - GREEN: Implement remaining verbosity levels
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Add verbosity levels 2-5 to formatter"
   - UPDATE: Mark task 3.3 complete in plan

**Task 3.4: Integrate formatter with SubsystemDebugger**
   - RED: Write test for SubsystemDebugger integration
   - GREEN: Wire formatter into existing debug output system
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Integrate formatter with SubsystemDebugger"
   - UPDATE: Mark task 3.4 complete in plan

**Task 3.5: Remove old formatter code**
   - RED: Update tests to remove expectations for old formatter
   - GREEN: Delete old display methods
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Remove old formatter code"
   - UPDATE: Mark task 3.5 complete in plan

### Phase 4: Update Clients [3-4 hours]

**Task 4.1: Update Anthropic client**
   - RED: Write test for internal format → Anthropic API translation
   - GREEN: Update `anthropic.rb` to accept and translate internal format
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Update Anthropic client to use internal format"
   - UPDATE: Mark task 4.1 complete in plan

**Task 4.2: Update OpenAI client**
   - RED: Write test for internal format → OpenAI API translation
   - GREEN: Update `openai.rb` to accept and translate internal format
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Update OpenAI client to use internal format"
   - UPDATE: Mark task 4.2 complete in plan

**Task 4.3: Update Google client**
   - RED: Write test for internal format → Google API translation
   - GREEN: Update `google.rb` to accept and translate internal format
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Update Google client to use internal format"
   - UPDATE: Mark task 4.3 complete in plan

**Task 4.4: Update XAI client**
   - RED: Write test for internal format → XAI API translation
   - GREEN: Update `xai.rb` to accept and translate internal format
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Update XAI client to use internal format"
   - UPDATE: Mark task 4.4 complete in plan

### Phase 5: Integration Testing [2 hours]

**Task 5.1: Create integration test for multi-turn conversations**
   - RED: Write integration test for multi-turn conversation flow
   - GREEN: Ensure all components work together
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Add integration test for multi-turn conversations"
   - UPDATE: Mark task 5.1 complete in plan

**Task 5.2: Create integration test for tool calling loops**
   - RED: Write integration test for tool calling flow
   - GREEN: Ensure tools parameter properly passed through all layers
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Add integration test for tool calling"
   - UPDATE: Mark task 5.2 complete in plan

**Task 5.3: Create integration test for debug output verbosity**
   - RED: Write integration test for all verbosity levels
   - GREEN: Ensure debug output filters correctly at each level
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Add integration test for debug verbosity"
   - UPDATE: Mark task 5.3 complete in plan

**Task 5.4: Performance validation**
   - RED: Write performance benchmark test
   - GREEN: Verify no significant overhead from builder pattern
   - REFACTOR: Optimize if needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Add performance validation test"
   - UPDATE: Mark task 5.4 complete in plan

### Phase 6: Cleanup [1 hour]

**Task 6.1: Remove orphaned code**
   - RED: Write test to ensure removed code is not referenced
   - GREEN: Remove old debug display logic and unused code
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Remove orphaned code"
   - UPDATE: Mark task 6.1 complete in plan

**Task 6.2: Add inline documentation**
   - RED: Write documentation linter test if applicable
   - GREEN: Add YARD/RDoc comments to new classes and methods
   - REFACTOR: Clean up as needed
   - RUN: `rake test && rake lint && rake coverage`
   - COMMIT: "Add inline documentation"
   - UPDATE: Mark task 6.2 complete in plan

### Phase 7: Manual Validation [Human verification required]

**IMPORTANT: These steps require HUMAN execution and verification**

**Task 7.1: Manual test with Anthropic client**
   - Start agent with Anthropic client
   - Test simple query with no tools
   - Test query requiring tool use
   - Test multi-turn conversation
   - Verify debug output at verbosity levels 0, 1, 3, 5
   - Verify no duplication of tool names in message content
   - UPDATE: Mark task 7.1 complete in plan

**Task 7.2: Manual test with OpenAI client**
   - Start agent with OpenAI client
   - Test simple query with no tools
   - Test query requiring tool use
   - Test multi-turn conversation
   - Verify debug output at verbosity levels 0, 1, 3, 5
   - Verify no duplication of tool names in message content
   - UPDATE: Mark task 7.2 complete in plan

**Task 7.3: Manual test with Google client**
   - Start agent with Google client
   - Test simple query with no tools
   - Test query requiring tool use
   - Test multi-turn conversation
   - Verify debug output at verbosity levels 0, 1, 3, 5
   - Verify no duplication of tool names in message content
   - UPDATE: Mark task 7.3 complete in plan

**Task 7.4: Manual test with XAI client**
   - Start agent with XAI client
   - Test simple query with no tools
   - Test query requiring tool use
   - Test multi-turn conversation
   - Verify debug output at verbosity levels 0, 1, 3, 5
   - Verify no duplication of tool names in message content
   - UPDATE: Mark task 7.4 complete in plan

**Task 7.5: Verify redaction still works**
   - Test with sensitive data in messages
   - Verify redaction properly applied in debug output
   - UPDATE: Mark task 7.5 complete in plan

**Task 7.6: Verify history storage unaffected**
   - Check conversation history in database
   - Verify proper storage of messages
   - Verify proper retrieval on conversation reload
   - UPDATE: Mark task 7.6 complete in plan

## Files to Modify

### New Files
- `lib/nu/agent/llm_request_builder.rb`
- `spec/nu/agent/llm_request_builder_spec.rb`

### Modified Files
- `lib/nu/agent/chat_loop_orchestrator.rb` - Use builder pattern
- `lib/nu/agent/formatters/llm_request_formatter.rb` - Replace with YAML output
- `lib/nu/agent/clients/anthropic.rb` - Accept internal format
- `lib/nu/agent/clients/openai.rb` - Accept internal format
- `lib/nu/agent/clients/google.rb` - Accept internal format
- `lib/nu/agent/clients/xai.rb` - Accept internal format
- `lib/nu/agent/tool_call_orchestrator.rb` - Pass internal format

### Test Files to Update
- `spec/nu/agent/chat_loop_orchestrator_spec.rb`
- `spec/nu/agent/formatter_spec.rb`
- `spec/nu/agent/clients/anthropic_spec.rb`
- `spec/nu/agent/clients/openai_spec.rb`
- `spec/nu/agent/clients/google_spec.rb`
- `spec/nu/agent/clients/xai_spec.rb`

### Files to Remove/Clean
- Remove "Available Tools" section generation (chat_loop_orchestrator.rb:217-219)
- Clean up old display methods in formatter

## Migration Strategy

1. **Parallel Implementation**: Build new system alongside existing
2. **Feature Flag**: Add temporary flag to switch between old/new
3. **Gradual Rollout**: Test with one client at a time
4. **Verification**: Ensure identical API requests sent
5. **Cleanup**: Remove old code once verified

## Success Criteria

- [ ] No duplication in message content (verified in Phase 7 manual testing)
- [ ] Consistent debug output format across all clients (verified in Phase 7)
- [ ] YAML debug output with verbosity filtering (verified in Phase 7)
- [ ] All tests passing (`rake test && rake lint && rake coverage` after each commit)
- [ ] No performance regression (verified in Phase 5.4)
- [ ] Tool calling loops still work (verified in Phases 5.2 and 7.x)
- [ ] Redaction still works (verified in Phase 7.5)
- [ ] History storage unaffected (verified in Phase 7.6)
- [ ] All tasks committed individually after passing tests
- [ ] Plan document updated after each task completion

## Risk Mitigation

1. **Breaking Changes**: Use feature flag for rollback
2. **Performance**: Profile before/after, optimize if needed
3. **Client Compatibility**: Test each client thoroughly
4. **Debug Output Size**: Add truncation later if needed
5. **YAML Serialization**: Handle special characters properly

## Future Enhancements

1. **Colorized YAML**: Add color coding for different sections
2. **Smart Truncation**: Truncate intelligently based on content
3. **Token Counting**: Show token counts in metadata
4. **Cost Calculation**: Show estimated cost in metadata
5. **Export Format**: Allow export of internal format for debugging

## Timeline Estimate

- Phase 1 (Builder): 2-3 hours
- Phase 2 (Orchestrator): 2-3 hours
- Phase 3 (Debug Display): 2-3 hours
- Phase 4 (Clients): 3-4 hours
- Phase 5 (Integration): 2 hours
- Phase 6 (Cleanup): 1 hour
- Phase 7 (Manual Testing): 2-3 hours (human verification)
- **Total: 14-19 hours**
- Can be done in phases
- Each phase independently testable
- No blocking dependencies between Phase 4 client updates

## Notes

- The internal format is never redacted - only debug display is filtered
- Empty/nil pruning happens only in client translation, not in builder
- System prompt date replacement happens in client, not builder
- Tool format conversion happens in client, not builder
- Metadata is for debugging only, not sent to LLM

## Review Checklist

- [ ] Does internal format cover all client needs?
- [ ] Is verbosity mapping intuitive?
- [ ] Are we handling all edge cases?
- [ ] Is migration strategy safe?
- [ ] Have we identified all code to clean up?