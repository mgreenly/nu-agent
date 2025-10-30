# Worker Refactoring Plan

## Objective
Reorganize background workers into `Nu::Agent::Workers` module for better scalability (30+ workers planned).

## Background Workers (3 total)
1. **ConversationSummarizer** - Summarizes completed conversations
2. **ExchangeSummarizer** - Summarizes individual exchanges
3. **EmbeddingPipeline** - Generates embeddings (rename to EmbeddingGenerator)

## File Moves

### Implementation Files
Move from `lib/nu/agent/` to `lib/nu/agent/workers/`:
- `conversation_summarizer.rb` → `workers/conversation_summarizer.rb`
- `exchange_summarizer.rb` → `workers/exchange_summarizer.rb`
- `embedding_pipeline.rb` → `workers/embedding_generator.rb`

### Spec Files
Move from `spec/nu/agent/` to `spec/nu/agent/workers/`:
- `conversation_summarizer_spec.rb` → `workers/conversation_summarizer_spec.rb`
- `exchange_summarizer_spec.rb` → `workers/exchange_summarizer_spec.rb`
- `embedding_pipeline_spec.rb` → `workers/embedding_generator_spec.rb`

## Namespace Changes

### Worker Classes
Change namespace from `Nu::Agent::` to `Nu::Agent::Workers::`:
- `Nu::Agent::ConversationSummarizer` → `Nu::Agent::Workers::ConversationSummarizer`
- `Nu::Agent::ExchangeSummarizer` → `Nu::Agent::Workers::ExchangeSummarizer`
- `Nu::Agent::EmbeddingPipeline` → `Nu::Agent::Workers::EmbeddingGenerator`

### Files to Update
1. `lib/nu/agent/workers/conversation_summarizer.rb`
   - Change module nesting to include `Workers`
2. `lib/nu/agent/workers/exchange_summarizer.rb`
   - Change module nesting to include `Workers`
3. `lib/nu/agent/workers/embedding_generator.rb`
   - Change module nesting to include `Workers`
   - Rename class from `EmbeddingPipeline` to `EmbeddingGenerator`
4. `lib/nu/agent/background_worker_manager.rb`
   - Update class references to use `Workers::` namespace
5. `spec/nu/agent/workers/conversation_summarizer_spec.rb`
   - Update RSpec.describe to use new namespace
6. `spec/nu/agent/workers/exchange_summarizer_spec.rb`
   - Update RSpec.describe to use new namespace
7. `spec/nu/agent/workers/embedding_generator_spec.rb`
   - Update RSpec.describe to use new namespace
   - Rename class references
8. `spec/nu/agent/background_worker_manager_spec.rb`
   - Update all class references to use `Workers::` namespace

## TDD Approach

### Phase 1: Move and Update Specs
1. Create `spec/nu/agent/workers/` directory
2. Move spec files to new location
3. Update namespaces in all spec files
4. Run `rake test` - tests will fail (classes not found)

### Phase 2: Move and Update Implementation
1. Create `lib/nu/agent/workers/` directory
2. Move implementation files to new location
3. Update namespaces in all worker files
4. Update `background_worker_manager.rb` with new namespaces
5. Run `rake test` - tests should pass

### Phase 3: Verify
1. Run `rake test` - all tests pass
2. Run `rake lint` - no violations
3. Run `rake coverage` - coverage maintained

## Success Criteria
- All tests passing
- No RuboCop violations
- All workers in `lib/nu/agent/workers/` directory
- All worker specs in `spec/nu/agent/workers/` directory
- Workers use `Nu::Agent::Workers::` namespace
- `EmbeddingPipeline` renamed to `EmbeddingGenerator`
