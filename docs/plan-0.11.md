# Nu-Agent v0.11 Implementation Plan: RAG System

**Last Updated**: 2025-10-29
**Current Version**: 0.9.0
**Target Version**: 0.11.0
**Plan Status**: Ready to execute
**GitHub Issue**: #17 (RAG Implementation)

---

## Table of Contents

1. [Executive Summary](#executive-summary) (Lines 20-45)
2. [Prerequisites & Context](#prerequisites--context) (Lines 47-89)
3. [Architecture Decision](#architecture-decision) (Lines 91-142)
4. [Implementation Phases](#implementation-phases) (Lines 144-185)
   - [Phase 0: Man-Page Infrastructure Removal](#phase-0-man-page-infrastructure-removal) (Lines 187-244)
   - [Phase 1: Database Schema Changes](#phase-1-database-schema-changes) (Lines 246-335)
   - [Phase 2: ExchangeSummarizer Worker](#phase-2-exchangesummarizer-worker) (Lines 337-424)
   - [Phase 3: EmbeddingPipeline Worker](#phase-3-embeddingpipeline-worker) (Lines 426-535)
   - [Phase 4: RAG Integration with Chain of Responsibility](#phase-4-rag-integration-with-chain-of-responsibility) (Lines 537-710)
   - [Phase 5: Command Interface](#phase-5-command-interface) (Lines 712-795)
   - [Phase 6: Testing & Documentation](#phase-6-testing--documentation) (Lines 797-860)
5. [Testing Strategy](#testing-strategy) (Lines 862-945)
6. [Configuration Reference](#configuration-reference) (Lines 947-1020)
7. [Success Criteria](#success-criteria) (Lines 1022-1080)
8. [Deferred Improvements (v0.12+)](#deferred-improvements-v012) (Lines 1082-1120)
9. [Notes for Future Sessions](#notes-for-future-sessions) (Lines 1122-1155)

---

## Executive Summary

### Goal

Implement Retrieval-Augmented Generation (RAG) to give the agent **conversational memory** - the ability to learn from and reference past interactions across conversations.

### Why This Approach

This plan **combines** the RAG implementation (from `rag-implementation-plan.md`) with **one critical architectural pattern** from `plan-0.11.md`:

- ✅ **Include**: Chain of Responsibility pattern for RAG pipeline (Goal 4)
- ❌ **Defer**: Application refactoring, Event-based messages, ConsoleIO State Pattern, Tool Decorators

**Rationale**: The Application class is already significantly improved (287 lines, down 43%). The Chain of Responsibility pattern should be implemented AS PART OF RAG (not as a separate refactoring), while other improvements can wait until v0.12+.

### What We're Building

1. **Exchange-level summarization** - Summarize each user-assistant exchange
2. **Embedding pipeline** - Generate vector embeddings for all summaries
3. **RAG retrieval** - Automatically retrieve relevant past context during queries
4. **Modular pipeline** - Use Chain of Responsibility pattern from the start

### Impact

The agent will automatically retrieve and reference relevant past conversations and exchanges when responding to new queries, creating a sense of continuity and accumulated knowledge.

---

## Prerequisites & Context

### Required Reading

Before starting, read these documents in order:

1. **docs/rag-implementation-plan.md** - Full RAG system design (this is the master reference)
2. **docs/architecture-analysis.md** - Current architecture patterns and recent improvements
3. **docs/design.md** - Database schema documentation
4. **lib/nu/agent/chat_loop_orchestrator.rb** - Orchestration patterns (264 lines)
5. **lib/nu/agent/background_worker_manager.rb** - Background worker management
6. **lib/nu/agent/history.rb** - Database facade and transaction management

### What Already Exists ✅

**Infrastructure:**
- DuckDB with `text_embedding_3_small` table
- `EmbeddingStore` class for managing embeddings
- `OpenAIEmbeddings` client (text-embedding-3-small model)
- `ConversationSummarizer` background worker (needs modification)
- `BackgroundWorkerManager` for thread lifecycle
- `conversations.summary` and `exchanges.summary` columns

**Architecture:**
- Transaction support via `History` facade
- Per-thread DuckDB connections
- Background worker patterns with status tracking
- Critical section management for database writes

### What's Missing ❌

- ExchangeSummarizer worker
- EmbeddingPipeline worker
- VSS extension enabled
- HNSW index on embeddings
- ConversationRetriever for semantic search
- Chain of Responsibility pattern for RAG pipeline
- fetch_conversation_details tool
- Command interface (/summarizer, /embeddings, /rag)

---

## Architecture Decision

### Why Include Chain of Responsibility Now?

The RAG pipeline has multiple processing stages:

```
User Query → Embed Query → Search Conversations → Search Exchanges → Build Context → Format
```

**Without Chain of Responsibility** (naive approach):
```ruby
class ChatLoopOrchestrator
  def retrieve_rag_context(user_input)
    # Hardcoded sequence
    query_embedding = embed_query(user_input)
    conversations = search_conversations(query_embedding)
    exchanges = search_exchanges(conversations)
    format_context(conversations, exchanges)
  end
end
```

**Problems with naive approach:**
- Cannot disable stages (e.g., for testing)
- Cannot reorder stages
- Cannot add new stages without modifying orchestrator
- Difficult to test stages in isolation

**With Chain of Responsibility** (our approach):
```ruby
class RagPipeline
  def initialize
    @pipeline = build_pipeline
  end

  def process(context)
    @pipeline.process(context)
  end

  private

  def build_pipeline
    # Configurable, testable, extensible
    QueryEmbeddingProcessor.new
      .set_next(ConversationSearchProcessor.new)
      .set_next(ExchangeSearchProcessor.new)
      .set_next(ContextFormatterProcessor.new)
  end
end
```

**Benefits:**
- ✅ Testable - Each processor is independent
- ✅ Configurable - Can skip/reorder stages
- ✅ Extensible - Add new stages without modifying ChatLoopOrchestrator
- ✅ Follows Open/Closed Principle
- ✅ Easier to add features later (caching, filtering, web search)

### Why Defer Other plan-0.11.md Goals?

| Goal | Why Defer |
|------|-----------|
| Complete Application refactoring | Application is already 287 lines (down 43%). Good enough for now. |
| Event-based message display | Performance optimization, not required for RAG. Polling works fine. |
| State Pattern in ConsoleIO | Internal refactoring, unrelated to RAG functionality. |
| Tool Decorators | Nice-to-have for cross-cutting concerns, but not blocking RAG. |

**These can be tackled in v0.12+ after RAG is working.**

---

## Implementation Phases

### Overview

| Phase | Description | Time | Priority |
|-------|-------------|------|----------|
| 0 | Remove man-page infrastructure | 30 min | High |
| 1 | Database schema (VSS, indexes) | 45 min | High |
| 2 | ExchangeSummarizer worker | 1.5 hrs | High |
| 3 | EmbeddingPipeline worker | 2 hrs | High |
| 4 | RAG Integration with Chain of Responsibility | 3 hrs | High |
| 5 | Command interface | 1.5 hrs | Medium |
| 6 | Testing & documentation | 1 hr | Medium |

**Total: ~10 hours of focused development**

### Execution Order

Phases must be done sequentially (each depends on the previous):
1. Phase 0 → Clean foundation
2. Phase 1 → Enable database features
3. Phases 2 & 3 → Workers (can be parallel, but sequential is easier)
4. Phase 4 → RAG integration
5. Phase 5 → Commands
6. Phase 6 → Testing

---

## Phase 0: Man-Page Infrastructure Removal

**Estimated time:** 30 minutes
**Priority:** HIGH (prerequisite for clean RAG foundation)

### Goal

Remove all man-page indexing code and clean up the database. This frees up the embedding infrastructure for conversational RAG.

### Why Remove Man-Pages?

- Less valuable than conversational memory
- Adds complexity and maintenance burden
- Uses embedding storage that should be for conversations
- Man pages are available via other tools (bash `man` command)

### Tasks

1. **Delete core classes:**
   ```bash
   rm lib/nu/agent/man_page_indexer.rb
   rm lib/nu/agent/man_indexer.rb
   rm lib/nu/agent/tools/man_indexer.rb
   rm lib/nu/agent/commands/index_man_command.rb
   ```

2. **Remove from integration points:**
   - `BackgroundWorkerManager`: Remove `man_indexer_status`, `start_man_indexer_worker()`, `build_man_indexer_status()`
   - `Application`: Remove `man_indexer_status` attr_reader
   - `ToolRegistry`: Unregister `man_indexer` tool
   - `lib/nu/agent.rb`: Remove requires for deleted files

3. **Delete test files:**
   ```bash
   rm spec/nu/agent/man_page_indexer_spec.rb
   rm spec/nu/agent/commands/index_man_command_spec.rb
   ```
   - Clean up references in `spec/nu/agent/background_worker_manager_spec.rb`

4. **Clean database:**
   ```ruby
   # In a Ruby console or migration
   history = History.new(db_path: "nu-agent.db")
   history.connection.query("DELETE FROM text_embedding_3_small WHERE kind = 'man_page'")
   ```

5. **Run test suite:**
   ```bash
   bundle exec rspec
   ```

6. **Update documentation:**
   - Remove man-page references from README
   - Update help text (if applicable)

### Validation Checklist

- [ ] All tests pass
- [ ] No references to "man" or "ManPage" in codebase (except man command tool)
- [ ] No man_page embeddings in database: `SELECT COUNT(*) FROM text_embedding_3_small WHERE kind = 'man_page'` returns 0
- [ ] Application starts without errors

### Git Commit

```bash
git add -A
git commit -m "Remove man-page indexing infrastructure

- Delete ManPageIndexer, ManIndexer, and related tools
- Remove man_indexer integration from BackgroundWorkerManager
- Clean up man_page embeddings from database
- Remove associated test files

Prepares codebase for RAG conversational memory implementation."
```

---

## Phase 1: Database Schema Changes

**Estimated time:** 45 minutes
**Priority:** HIGH (enables all subsequent phases)

### Goal

Enable DuckDB Vector Similarity Search (VSS) extension, add foreign keys to embeddings table, create HNSW index for fast similarity search.

### Tasks

#### 1. Enable VSS Extension

Add to `SchemaManager` class:

```ruby
def enable_vss_extension
  @connection.query("INSTALL vss") unless vss_installed?
  @connection.query("LOAD vss")
rescue DuckDB::Error => e
  # VSS extension is included in DuckDB 1.4.1+
  raise "VSS extension not available: #{e.message}"
end

private

def vss_installed?
  result = @connection.query("SELECT * FROM duckdb_extensions() WHERE extension_name = 'vss'")
  result.any?
end
```

Call during `setup_database()` method.

#### 2. Add Foreign Key Columns to Embeddings Table

```ruby
def migrate_embeddings_table
  @connection.query(<<~SQL)
    ALTER TABLE text_embedding_3_small
      ADD COLUMN IF NOT EXISTS conversation_id INTEGER REFERENCES conversations(id);

    ALTER TABLE text_embedding_3_small
      ADD COLUMN IF NOT EXISTS exchange_id INTEGER REFERENCES exchanges(id);
  SQL
end
```

**Migration Strategy:**
Since we just deleted all man_page embeddings, and there are no other embeddings yet, this is a clean migration. Future embeddings will use the foreign keys.

#### 3. Create Indexes

```ruby
def create_embedding_indexes
  @connection.query(<<~SQL)
    CREATE INDEX IF NOT EXISTS idx_embedding_conversation
      ON text_embedding_3_small(conversation_id);

    CREATE INDEX IF NOT EXISTS idx_embedding_exchange
      ON text_embedding_3_small(exchange_id);

    CREATE INDEX IF NOT EXISTS embedding_hnsw_idx
      ON text_embedding_3_small
      USING HNSW (embedding);
  SQL
end
```

**What is HNSW?**
- Hierarchical Navigable Small Worlds
- Approximate nearest neighbor search algorithm
- Fast similarity queries on high-dimensional vectors
- O(log N) vs O(N) for linear scan

#### 4. Add Similarity Search Methods to EmbeddingStore

```ruby
class EmbeddingStore
  # Search conversation summaries by similarity
  def search_similar_conversations(query_embedding:, limit:, min_similarity:, exclude_conversation_id: nil)
    exclude_clause = exclude_conversation_id ? "AND conversation_id != #{exclude_conversation_id}" : ""

    result = @connection.query(<<~SQL)
      SELECT
        conversation_id,
        content,
        array_cosine_similarity(embedding, #{format_embedding(query_embedding)}) as similarity
      FROM text_embedding_3_small
      WHERE kind = 'conversation_summary'
        #{exclude_clause}
        AND array_cosine_similarity(embedding, #{format_embedding(query_embedding)}) >= #{min_similarity}
      ORDER BY similarity DESC
      LIMIT #{limit}
    SQL

    result.map { |row| { conversation_id: row[0], content: row[1], similarity: row[2] } }
  end

  # Search exchange summaries within specific conversations
  def search_similar_exchanges(query_embedding:, conversation_ids:, limit_per_conversation:, min_similarity:)
    ids_list = conversation_ids.join(', ')

    result = @connection.query(<<~SQL)
      WITH ranked_exchanges AS (
        SELECT
          exchange_id,
          conversation_id,
          content,
          array_cosine_similarity(embedding, #{format_embedding(query_embedding)}) as similarity,
          ROW_NUMBER() OVER (
            PARTITION BY conversation_id
            ORDER BY array_cosine_similarity(embedding, #{format_embedding(query_embedding)}) DESC
          ) as rank
        FROM text_embedding_3_small
        WHERE kind = 'exchange_summary'
          AND conversation_id IN (#{ids_list})
          AND array_cosine_similarity(embedding, #{format_embedding(query_embedding)}) >= #{min_similarity}
      )
      SELECT exchange_id, conversation_id, content, similarity
      FROM ranked_exchanges
      WHERE rank <= #{limit_per_conversation}
      ORDER BY similarity DESC
    SQL

    result.map { |row| { exchange_id: row[0], conversation_id: row[1], content: row[2], similarity: row[3] } }
  end

  private

  def format_embedding(embedding_array)
    "[#{embedding_array.join(', ')}]"
  end
end
```

### Validation Checklist

- [ ] VSS extension loads without error
- [ ] HNSW index created successfully
- [ ] Foreign key constraints work (test with dummy data)
- [ ] `search_similar_conversations` returns results ordered by similarity
- [ ] `search_similar_exchanges` respects `limit_per_conversation` (window function works)
- [ ] All existing tests pass

### Manual Testing

```ruby
# In Rails console or Ruby script
embeddings_client = Clients::OpenAIEmbeddings.new
query_embedding = embeddings_client.embed("test query")
results = embedding_store.search_similar_conversations(
  query_embedding: query_embedding,
  limit: 5,
  min_similarity: 0.5
)
puts results.inspect
```

### Git Commit

```bash
git add -A
git commit -m "Add VSS extension and similarity search for RAG

- Enable DuckDB VSS extension with HNSW index
- Add foreign keys (conversation_id, exchange_id) to embeddings table
- Implement search_similar_conversations and search_similar_exchanges
- Create indexes for fast similarity queries

Enables semantic search for RAG conversational memory."
```

---

## Phase 2: ExchangeSummarizer Worker

**Estimated time:** 1.5 hours
**Priority:** HIGH

### Goal

Create a background worker that continuously monitors for completed exchanges without summaries, generates 1-2 sentence summaries using an LLM, and stores them in the database.

### Architecture

**Behavior:**
- Continuous daemon mode (runs until stopped)
- Finds exchanges WHERE `summary IS NULL AND status = 'completed'`
- Excludes exchanges from current conversation
- Orders by `completed_at DESC` (newest first)
- Signals embedding pipeline after each summary
- Idle state with condition variable (wake on signal or 30s timeout)

### Tasks

#### 1. Create ExchangeSummarizer Class

Create `lib/nu/agent/exchange_summarizer.rb`:

```ruby
module Nu
  module Agent
    class ExchangeSummarizer
      def initialize(history:, client:, application:, conversation_id:)
        @history = history
        @client = client
        @application = application
        @conversation_id = conversation_id
        @shutdown = false
        @mutex = Mutex.new
        @condition_variable = ConditionVariable.new
        @status = {
          state: 'idle',
          completed: 0,
          failed: 0,
          current_exchange_id: nil
        }
      end

      def start_worker
        Thread.new do
          run_continuously
        rescue StandardError => e
          @application.output_line("[ExchangeSummarizer] Fatal error: #{e.message}", type: :error)
          raise
        end
      end

      def signal
        @mutex.synchronize { @condition_variable.signal }
      end

      def shutdown
        @shutdown = true
        signal
      end

      def status
        @mutex.synchronize { @status.dup }
      end

      private

      def run_continuously
        loop do
          break if @shutdown

          exchanges = find_unsummarized_exchanges

          if exchanges.empty?
            set_status_idle
            wait_for_signal_or_timeout(30) # 30 seconds
            next
          end

          set_status_running(exchanges.length)

          exchanges.each do |exchange|
            break if @shutdown
            process_exchange(exchange)
          end
        end
      end

      def find_unsummarized_exchanges
        @history.get_unsummarized_exchanges(
          exclude_conversation_id: @conversation_id.call,
          limit: 100
        )
      end

      def process_exchange(exchange)
        @status[:current_exchange_id] = exchange['id']

        summary = generate_summary(exchange)

        @application.send(:enter_critical_section)
        @history.update_exchange_summary(
          exchange_id: exchange['id'],
          summary: summary,
          model: @client.model_id,
          cost: 0.001 # Approximate, should calculate from usage
        )
        @application.send(:exit_critical_section)

        @status[:completed] += 1
        @status[:current_exchange_id] = nil

        # Signal embedding pipeline
        @application.instance_variable_get(:@background_worker_manager)
          &.signal_embedding_pipeline
      rescue StandardError => e
        @status[:failed] += 1
        @application.output_line(
          "[ExchangeSummarizer] Failed to summarize exchange #{exchange['id']}: #{e.message}",
          type: :error
        )
      end

      def generate_summary(exchange)
        prompt = build_summary_prompt(exchange)
        response = @client.send_message([{ role: 'user', content: prompt }])
        response.dig(:content, 0, :text) || ''
      end

      def build_summary_prompt(exchange)
        <<~PROMPT
          Summarize this exchange concisely in 1-2 sentences.
          Focus on: what the user asked, what action was taken, and the outcome.

          User: #{exchange['user_message']}
          Assistant: #{exchange['assistant_message']}

          Provide ONLY the summary, no preamble.
        PROMPT
      end

      def set_status_idle
        @mutex.synchronize { @status[:state] = 'idle' }
      end

      def set_status_running(count)
        @mutex.synchronize { @status[:state] = "running (#{count} pending)" }
      end

      def wait_for_signal_or_timeout(seconds)
        @mutex.synchronize do
          @condition_variable.wait(@mutex, seconds)
        end
      end
    end
  end
end
```

#### 2. Add History Methods

Add to `History` class:

```ruby
def get_unsummarized_exchanges(exclude_conversation_id:, limit: 100)
  @exchange_repo.get_unsummarized_exchanges(
    exclude_conversation_id: exclude_conversation_id,
    limit: limit
  )
end

def update_exchange_summary(exchange_id:, summary:, model:, cost:)
  @exchange_repo.update_exchange_summary(
    exchange_id: exchange_id,
    summary: summary,
    model: model,
    cost: cost
  )
end
```

Add to `ExchangeRepository`:

```ruby
def get_unsummarized_exchanges(exclude_conversation_id:, limit:)
  result = @connection.query(<<~SQL)
    SELECT * FROM exchanges
    WHERE summary IS NULL
      AND status = 'completed'
      AND conversation_id != #{exclude_conversation_id}
    ORDER BY completed_at DESC
    LIMIT #{limit}
  SQL

  result.to_a
end

def update_exchange_summary(exchange_id:, summary:, model:, cost:)
  @connection.query(<<~SQL)
    UPDATE exchanges
    SET summary = '#{escape_sql(summary)}',
        summary_model = '#{escape_sql(model)}',
        summary_cost = #{cost}
    WHERE id = #{exchange_id}
  SQL
end

private

def escape_sql(str)
  str.gsub("'", "''")
end
```

#### 3. Integrate with BackgroundWorkerManager

Add to `BackgroundWorkerManager`:

```ruby
attr_reader :exchange_summarizer_status

def initialize(...)
  # ... existing code ...
  @exchange_summarizer = nil
  @exchange_summarizer_status = build_exchange_summarizer_status
end

def start_exchange_summarizer_worker
  return if @exchange_summarizer

  token = @application.send(:allocate_worker_token)

  @exchange_summarizer = ExchangeSummarizer.new(
    history: @history,
    client: create_summarizer_client,
    application: @application,
    conversation_id: -> { @application.instance_variable_get(:@conversation_id) }
  )

  thread = @exchange_summarizer.start_worker
  @active_threads << thread
  token.activate
end

def signal_exchange_summarizer
  @exchange_summarizer&.signal
end

def stop_exchange_summarizer_worker
  return unless @exchange_summarizer

  @exchange_summarizer.shutdown
  @exchange_summarizer = nil
end

private

def build_exchange_summarizer_status
  -> { @exchange_summarizer&.status || { state: 'stopped' } }
end
```

#### 4. Add to Application

```ruby
attr_reader :exchange_summarizer_status

def start_exchange_summarizer_worker
  @background_worker_manager.start_exchange_summarizer_worker
end

def stop_exchange_summarizer_worker
  @background_worker_manager.stop_exchange_summarizer_worker
end
```

### Validation Checklist

- [ ] Worker finds unsummarized exchanges
- [ ] Worker excludes current conversation
- [ ] Summaries stored in `exchanges.summary` column
- [ ] Worker goes idle when no work
- [ ] Worker wakes on signal
- [ ] Signals embedding pipeline after each summary
- [ ] All existing tests pass

### Manual Testing

```ruby
# Create exchanges manually
history.create_exchange(...)
history.complete_exchange(...)

# Start worker
application.start_exchange_summarizer_worker

# Check status
application.exchange_summarizer_status.call

# Check summaries
history.connection.query("SELECT id, summary FROM exchanges WHERE summary IS NOT NULL")
```

### Git Commit

```bash
git add -A
git commit -m "Add ExchangeSummarizer background worker

- Create ExchangeSummarizer class with continuous daemon mode
- Add get_unsummarized_exchanges and update_exchange_summary to History
- Integrate with BackgroundWorkerManager and Application
- Signal embedding pipeline after each summary
- Exclude current conversation from summarization

Enables automatic exchange-level summarization for RAG."
```

---

## Phase 3: EmbeddingPipeline Worker

**Estimated time:** 2 hours
**Priority:** HIGH

### Goal

Create a background worker that continuously monitors for summaries without embeddings, generates embeddings in batches, stores them with foreign keys, and implements exponential backoff retry logic for API failures.

### Architecture

**Behavior:**
- Continuous daemon mode (runs until stopped)
- Finds conversations/exchanges with summaries but no embeddings (LEFT JOIN)
- Batch embeds (up to 100 items per API call)
- Stores embeddings atomically (entire batch or none)
- Exponential backoff on failures (1s, 2s, 4s, 8s, 16s, 32s, give up)
- Signal + 5-second fallback poll

### Tasks

#### 1. Create EmbeddingPipeline Class

Create `lib/nu/agent/embedding_pipeline.rb`:

```ruby
module Nu
  module Agent
    class EmbeddingPipeline
      def initialize(history:, embeddings_client:, application:)
        @history = history
        @embeddings_client = embeddings_client
        @application = application
        @shutdown = false
        @mutex = Mutex.new
        @condition_variable = ConditionVariable.new
        @retry_queue = {}
        @status = {
          state: 'idle',
          completed: 0,
          failed: 0,
          retry_queue_size: 0
        }
      end

      def start_worker
        Thread.new do
          run_continuously
        rescue StandardError => e
          @application.output_line("[EmbeddingPipeline] Fatal error: #{e.message}", type: :error)
          raise
        end
      end

      def signal
        @mutex.synchronize { @condition_variable.signal }
      end

      def shutdown
        @shutdown = true
        signal
      end

      def status
        @mutex.synchronize { @status.dup }
      end

      private

      def run_continuously
        loop do
          break if @shutdown

          # Find work
          conversations = @history.find_conversations_needing_embeddings(limit: 100)
          exchanges = @history.find_exchanges_needing_embeddings(limit: 100)
          retries = get_items_ready_for_retry

          all_items = conversations + exchanges + retries

          if all_items.empty?
            set_status_idle
            wait_for_signal_or_timeout(5) # Fast poll - 5 seconds
            next
          end

          set_status_running(all_items.length)
          process_batch_with_retry(all_items)
        end
      end

      def process_batch_with_retry(items)
        texts = items.map { |item| item['summary'] }

        begin
          embeddings = @embeddings_client.embed_batch(texts)
          store_embeddings_atomically(items, embeddings)
          remove_from_retry_queue(items)
          @status[:completed] += items.length
        rescue StandardError => e
          handle_failure_with_backoff(items, e)
        end
      end

      def store_embeddings_atomically(items, embeddings)
        @application.send(:enter_critical_section)

        @history.transaction do
          items.zip(embeddings).each do |item, embedding|
            if item['created_at'] # Conversations have created_at, exchanges have started_at
              @history.store_conversation_embedding(
                conversation_id: item['id'],
                content: item['summary'],
                embedding: embedding
              )
            else
              @history.store_exchange_embedding(
                exchange_id: item['id'],
                content: item['summary'],
                embedding: embedding
              )
            end
          end
        end
      ensure
        @application.send(:exit_critical_section)
      end

      def handle_failure_with_backoff(items, error)
        items.each do |item|
          key = item_key(item)
          attempts = @retry_queue[key]&.fetch(:attempts, 0) || 0
          next_retry = Time.now + (2**attempts) # 1s, 2s, 4s, 8s, 16s, 32s

          if attempts >= 6
            @status[:failed] += 1
            @application.output_line(
              "[EmbeddingPipeline] Permanent failure for #{key}: #{error.message}",
              type: :error
            )
          else
            @retry_queue[key] = {
              attempts: attempts + 1,
              next_retry: next_retry,
              item: item,
              error: error.message
            }
            @status[:retry_queue_size] = @retry_queue.size
          end
        end
      end

      def get_items_ready_for_retry
        now = Time.now
        @retry_queue.select { |_key, entry| entry[:next_retry] <= now }
                    .map { |_key, entry| entry[:item] }
      end

      def remove_from_retry_queue(items)
        items.each do |item|
          @retry_queue.delete(item_key(item))
        end
        @status[:retry_queue_size] = @retry_queue.size
      end

      def item_key(item)
        if item['created_at']
          "conversation_#{item['id']}"
        else
          "exchange_#{item['id']}"
        end
      end

      def set_status_idle
        @mutex.synchronize { @status[:state] = 'idle' }
      end

      def set_status_running(count)
        @mutex.synchronize { @status[:state] = "running (#{count} pending)" }
      end

      def wait_for_signal_or_timeout(seconds)
        @mutex.synchronize do
          @condition_variable.wait(@mutex, seconds)
        end
      end
    end
  end
end
```

#### 2. Add History Methods

Add to `History`:

```ruby
def find_conversations_needing_embeddings(limit:)
  result = @connection.query(<<~SQL)
    SELECT c.* FROM conversations c
    LEFT JOIN text_embedding_3_small e
      ON e.conversation_id = c.id AND e.kind = 'conversation_summary'
    WHERE c.summary IS NOT NULL
      AND e.id IS NULL
    LIMIT #{limit}
  SQL

  result.to_a
end

def find_exchanges_needing_embeddings(limit:)
  result = @connection.query(<<~SQL)
    SELECT e.* FROM exchanges e
    LEFT JOIN text_embedding_3_small emb
      ON emb.exchange_id = e.id AND emb.kind = 'exchange_summary'
    WHERE e.summary IS NOT NULL
      AND emb.id IS NULL
    LIMIT #{limit}
  SQL

  result.to_a
end

def store_conversation_embedding(conversation_id:, content:, embedding:)
  @embedding_store.store_embedding(
    kind: 'conversation_summary',
    conversation_id: conversation_id,
    exchange_id: nil,
    content: content,
    embedding: embedding
  )
end

def store_exchange_embedding(exchange_id:, content:, embedding:)
  @embedding_store.store_embedding(
    kind: 'exchange_summary',
    conversation_id: nil,
    exchange_id: exchange_id,
    content: content,
    embedding: embedding
  )
end
```

Update `EmbeddingStore#store_embedding`:

```ruby
def store_embedding(kind:, conversation_id:, exchange_id:, content:, embedding:)
  embedding_str = format_embedding(embedding)

  @connection.query(<<~SQL)
    INSERT INTO text_embedding_3_small
      (kind, conversation_id, exchange_id, content, embedding)
    VALUES
      ('#{escape_sql(kind)}',
       #{conversation_id || 'NULL'},
       #{exchange_id || 'NULL'},
       '#{escape_sql(content)}',
       #{embedding_str})
  SQL
end

private

def escape_sql(str)
  str.gsub("'", "''")
end

def format_embedding(embedding_array)
  "[#{embedding_array.join(', ')}]"
end
```

#### 3. Integrate with BackgroundWorkerManager

Add to `BackgroundWorkerManager`:

```ruby
attr_reader :embedding_pipeline_status

def initialize(...)
  # ... existing code ...
  @embedding_pipeline = nil
  @embedding_pipeline_status = build_embedding_pipeline_status
end

def start_embedding_pipeline_worker
  return if @embedding_pipeline

  token = @application.send(:allocate_worker_token)

  @embedding_pipeline = EmbeddingPipeline.new(
    history: @history,
    embeddings_client: Clients::OpenAIEmbeddings.new,
    application: @application
  )

  thread = @embedding_pipeline.start_worker
  @active_threads << thread
  token.activate
end

def signal_embedding_pipeline
  @embedding_pipeline&.signal
end

def stop_embedding_pipeline_worker
  return unless @embedding_pipeline

  @embedding_pipeline.shutdown
  @embedding_pipeline = nil
end

private

def build_embedding_pipeline_status
  -> { @embedding_pipeline&.status || { state: 'stopped' } }
end
```

#### 4. Wire Up Signals

In `ChatLoopOrchestrator#complete_exchange`:

```ruby
def complete_exchange(exchange_id, ...)
  @history.complete_exchange(exchange_id: exchange_id, ...)

  # Signal workers
  @application.instance_variable_get(:@background_worker_manager)&.tap do |manager|
    manager.signal_exchange_summarizer
    manager.signal_embedding_pipeline
  end
end
```

In `ConversationSummarizer` (modify existing):

```ruby
def process_conversation(conversation)
  # ... existing code ...

  # Signal embedding pipeline after summary
  @application.instance_variable_get(:@background_worker_manager)
    &.signal_embedding_pipeline
end
```

### Validation Checklist

- [ ] Worker finds summaries without embeddings (LEFT JOIN works)
- [ ] Batches multiple summaries per API call
- [ ] Stores embeddings with correct foreign keys
- [ ] Retry queue handles failures with exponential backoff
- [ ] Worker wakes immediately on signal
- [ ] Falls back to 5-second polling
- [ ] All existing tests pass

### Manual Testing

```bash
# Create summaries
application.start_conversation_summarizer_worker
application.start_exchange_summarizer_worker

# Start embedding pipeline
application.start_embedding_pipeline_worker

# Check status
application.embedding_pipeline_status.call

# Verify embeddings
history.connection.query("SELECT conversation_id, exchange_id, kind FROM text_embedding_3_small")

# Test failure handling (break API key, verify retry queue)
```

### Git Commit

```bash
git add -A
git commit -m "Add EmbeddingPipeline background worker with retry logic

- Create EmbeddingPipeline class with continuous daemon mode
- Implement batching (up to 100 embeddings per API call)
- Add exponential backoff retry queue (1s to 32s)
- Store embeddings atomically with foreign keys
- Wire up signals from ConversationSummarizer and ExchangeSummarizer
- Add find_*_needing_embeddings methods to History

Enables automatic embedding generation for all summaries."
```

---

## Phase 4: RAG Integration with Chain of Responsibility

**Estimated time:** 3 hours
**Priority:** HIGH (core RAG functionality)

### Goal

Implement the RAG retrieval system using the Chain of Responsibility pattern for the processing pipeline. This includes:
1. Context processors (Chain of Responsibility pattern)
2. ConversationRetriever for semantic search
3. Integration with ChatLoopOrchestrator
4. fetch_conversation_details tool

### Part A: Context Processors (Chain of Responsibility)

#### 1. Create Base Processor

Create `lib/nu/agent/context_processors/context_processor.rb`:

```ruby
module Nu
  module Agent
    module ContextProcessors
      class ContextProcessor
        def initialize
          @next_processor = nil
        end

        def set_next(processor)
          @next_processor = processor
          processor
        end

        def process(context)
          result = do_process(context)

          if @next_processor
            @next_processor.process(result)
          else
            result
          end
        end

        protected

        def do_process(context)
          # Override in subclasses
          context
        end
      end
    end
  end
end
```

#### 2. Create Query Embedding Processor

Create `lib/nu/agent/context_processors/query_embedding_processor.rb`:

```ruby
module Nu
  module Agent
    module ContextProcessors
      class QueryEmbeddingProcessor < ContextProcessor
        def initialize(embeddings_client:)
          super()
          @embeddings_client = embeddings_client
        end

        protected

        def do_process(context)
          query_text = context[:query_text]
          query_embedding = @embeddings_client.embed(query_text)

          context.merge(query_embedding: query_embedding)
        end
      end
    end
  end
end
```

#### 3. Create Conversation Search Processor

Create `lib/nu/agent/context_processors/conversation_search_processor.rb`:

```ruby
module Nu
  module Agent
    module ContextProcessors
      class ConversationSearchProcessor < ContextProcessor
        def initialize(history:, config:)
          super()
          @history = history
          @config = config
        end

        protected

        def do_process(context)
          similar_convos = @history.embedding_store.search_similar_conversations(
            query_embedding: context[:query_embedding],
            limit: @config.fetch('rag_conversation_limit', 3),
            min_similarity: @config.fetch('rag_min_similarity', 0.7),
            exclude_conversation_id: context[:current_conversation_id]
          )

          context.merge(similar_conversations: similar_convos)
        end
      end
    end
  end
end
```

#### 4. Create Exchange Search Processor

Create `lib/nu/agent/context_processors/exchange_search_processor.rb`:

```ruby
module Nu
  module Agent
    module ContextProcessors
      class ExchangeSearchProcessor < ContextProcessor
        def initialize(history:, config:)
          super()
          @history = history
          @config = config
        end

        protected

        def do_process(context)
          return context if context[:similar_conversations].empty?

          conversation_ids = context[:similar_conversations].map { |c| c[:conversation_id] }

          similar_exchanges = @history.embedding_store.search_similar_exchanges(
            query_embedding: context[:query_embedding],
            conversation_ids: conversation_ids,
            limit_per_conversation: @config.fetch('rag_exchange_limit_per_conversation', 2),
            min_similarity: @config.fetch('rag_min_similarity', 0.7)
          )

          context.merge(similar_exchanges: similar_exchanges)
        end
      end
    end
  end
end
```

#### 5. Create Context Formatter Processor

Create `lib/nu/agent/context_processors/context_formatter_processor.rb`:

```ruby
module Nu
  module Agent
    module ContextProcessors
      class ContextFormatterProcessor < ContextProcessor
        def initialize(history:)
          super()
          @history = history
        end

        protected

        def do_process(context)
          conversations = context[:similar_conversations].map do |conv_data|
            enrich_conversation(conv_data)
          end

          exchanges = context[:similar_exchanges].map do |exch_data|
            enrich_exchange(exch_data)
          end

          context.merge(
            rag_context: {
              conversations: conversations,
              exchanges: exchanges
            }
          )
        end

        private

        def enrich_conversation(conv_data)
          conv = @history.get_conversation(conv_data[:conversation_id])
          {
            id: conv['id'],
            title: conv['title'],
            summary: conv_data[:content],
            similarity: conv_data[:similarity],
            created_at: conv['created_at'],
            exchange_count: @history.count_exchanges(conv['id'])
          }
        end

        def enrich_exchange(exch_data)
          exch = @history.get_exchange(exch_data[:exchange_id])
          {
            id: exch['id'],
            conversation_id: exch['conversation_id'],
            summary: exch_data[:content],
            similarity: exch_data[:similarity],
            user_message: truncate(exch['user_message'], 200),
            assistant_message: truncate(exch['assistant_message'], 200),
            completed_at: exch['completed_at']
          }
        end

        def truncate(text, length)
          return text if text.length <= length
          "#{text[0...length]}..."
        end
      end
    end
  end
end
```

### Part B: ConversationRetriever (Pipeline Coordinator)

Create `lib/nu/agent/conversation_retriever.rb`:

```ruby
module Nu
  module Agent
    class ConversationRetriever
      def initialize(history:, embeddings_client:, config:)
        @history = history
        @embeddings_client = embeddings_client
        @config = config
        @pipeline = build_pipeline
      end

      def retrieve_related_context(query_text:, current_conversation_id:)
        context = {
          query_text: query_text,
          current_conversation_id: current_conversation_id
        }

        result = @pipeline.process(context)
        result[:rag_context]
      rescue StandardError => e
        # Graceful degradation
        Rails.logger.error("[RAG] Retrieval failed: #{e.message}")
        nil
      end

      private

      def build_pipeline
        ContextProcessors::QueryEmbeddingProcessor.new(embeddings_client: @embeddings_client)
          .set_next(ContextProcessors::ConversationSearchProcessor.new(history: @history, config: @config))
          .set_next(ContextProcessors::ExchangeSearchProcessor.new(history: @history, config: @config))
          .set_next(ContextProcessors::ContextFormatterProcessor.new(history: @history))
      end
    end
  end
end
```

### Part C: Integration with ChatLoopOrchestrator

Update `ChatLoopOrchestrator`:

```ruby
def execute(user_input)
  exchange_id = @history.create_exchange(...)

  # NEW: Retrieve RAG context if enabled
  rag_context = retrieve_rag_context_if_enabled(user_input)

  # Build context with RAG data
  context_doc = @document_builder.build(
    conversation_history: @history.messages(...),
    tools: @tool_registry.tools,
    user_query: user_input,
    rag_context: rag_context  # NEW parameter
  )

  # Rest of existing flow...
  response = @client.send_message(context_doc, tools: ...)
  # ... tool loop ...
  @history.complete_exchange(exchange_id, ...)

  # Signal workers (already done in Phase 3)
end

private

def retrieve_rag_context_if_enabled(user_input)
  return nil unless rag_enabled?

  retriever = ConversationRetriever.new(
    history: @history,
    embeddings_client: Clients::OpenAIEmbeddings.new,
    config: @config_store
  )

  retriever.retrieve_related_context(
    query_text: user_input,
    current_conversation_id: @conversation_id
  )
rescue StandardError => e
  @application.output_line("[RAG] Retrieval failed: #{e.message}", type: :error)
  nil # Graceful degradation
end

def rag_enabled?
  @config_store.get('rag_enabled', true)
end
```

### Part D: Update DocumentBuilder

Add RAG section to context document:

```ruby
def build(conversation_history:, tools:, user_query:, rag_context: nil)
  sections = []

  sections << build_system_section
  sections << build_rag_section(rag_context) if rag_context && rag_context[:conversations]&.any?
  sections << build_conversation_history_section(conversation_history)
  sections << build_tools_section(tools)
  sections << build_user_query_section(user_query)

  sections.join("\n\n---\n\n")
end

private

def build_rag_section(rag_context)
  <<~MARKDOWN
    ## Related Past Conversations

    The following conversations and exchanges may be relevant to the current query.
    You can use the `fetch_conversation_details` tool to get more information about any conversation or exchange using the IDs provided below.

    #{format_conversations(rag_context[:conversations])}

    #{format_exchanges(rag_context[:exchanges])}
  MARKDOWN
end

def format_conversations(conversations)
  conversations.map do |conv|
    <<~CONV
      ### Conversation: "#{conv[:title]}" (ID: #{conv[:id]}, Date: #{conv[:created_at]}, Similarity: #{conv[:similarity].round(2)})
      Summary: #{conv[:summary]}
      Exchanges: #{conv[:exchange_count]}
    CONV
  end.join("\n")
end

def format_exchanges(exchanges)
  return "" if exchanges.empty?

  "\n#### Relevant Exchanges:\n\n" + exchanges.map do |exch|
    <<~EXCH
      **Exchange ID: #{exch[:id]}** (Conversation: #{exch[:conversation_id]}, Similarity: #{exch[:similarity].round(2)})
      - User: #{exch[:user_message]}
      - Assistant: #{exch[:assistant_message]}
    EXCH
  end.join("\n")
end
```

### Part E: fetch_conversation_details Tool

Create `lib/nu/agent/tools/fetch_conversation_details.rb`:

```ruby
module Nu
  module Agent
    module Tools
      class FetchConversationDetails
        def name
          'fetch_conversation_details'
        end

        def description
          'Fetch detailed information about a specific conversation or exchange from past interactions. ' \
          'Use the IDs provided in the RAG context metadata.'
        end

        def parameters
          {
            conversation_id: {
              type: 'integer',
              description: 'Conversation ID from RAG context. Get full conversation details.',
              required: false
            },
            exchange_id: {
              type: 'integer',
              description: 'Specific exchange ID from RAG context. Get single exchange details.',
              required: false
            },
            include_full_transcript: {
              type: 'boolean',
              description: 'Include all messages (tool calls, intermediate steps), not just user/assistant pairs.',
              default: false,
              required: false
            }
          }
        end

        def execute(arguments:, history:, context:)
          conversation_id = arguments['conversation_id']
          exchange_id = arguments['exchange_id']
          include_full = arguments.fetch('include_full_transcript', false)

          if exchange_id
            fetch_exchange_details(history, exchange_id, include_full)
          elsif conversation_id
            fetch_conversation_details(history, conversation_id, include_full)
          else
            { 'error' => 'Must provide either conversation_id or exchange_id' }
          end
        end

        private

        def fetch_conversation_details(history, conversation_id, include_full)
          conversation = history.get_conversation(conversation_id)
          return { 'error' => 'Conversation not found' } unless conversation

          exchanges = history.exchanges(conversation_id: conversation_id)

          {
            'conversation_id' => conversation['id'],
            'title' => conversation['title'],
            'summary' => conversation['summary'],
            'created_at' => conversation['created_at'],
            'status' => conversation['status'],
            'exchanges' => exchanges.map { |exch| format_exchange(exch, include_full, history) }
          }
        end

        def fetch_exchange_details(history, exchange_id, include_full)
          exchange = history.get_exchange(exchange_id)
          return { 'error' => 'Exchange not found' } unless exchange

          {
            'exchange_id' => exchange['id'],
            'conversation_id' => exchange['conversation_id'],
            'summary' => exchange['summary'],
            'user_message' => exchange['user_message'],
            'assistant_message' => exchange['assistant_message'],
            'started_at' => exchange['started_at'],
            'completed_at' => exchange['completed_at'],
            'messages' => include_full ? fetch_full_messages(history, exchange_id) : nil
          }
        end

        def format_exchange(exchange, include_full, history)
          result = {
            'exchange_id' => exchange['id'],
            'summary' => exchange['summary'],
            'user_message' => exchange['user_message'],
            'assistant_message' => exchange['assistant_message'],
            'completed_at' => exchange['completed_at']
          }

          result['messages'] = fetch_full_messages(history, exchange['id']) if include_full
          result
        end

        def fetch_full_messages(history, exchange_id)
          history.messages(exchange_id: exchange_id).map do |msg|
            {
              'role' => msg['role'],
              'content' => msg['content'],
              'tool_calls' => msg['tool_calls'],
              'tool_result' => msg['tool_result']
            }
          end
        end
      end
    end
  end
end
```

Register in `ToolRegistry`:

```ruby
register_tool(Tools::FetchConversationDetails.new)
```

### Validation Checklist

- [ ] Chain of Responsibility pattern works (can add/remove/reorder processors)
- [ ] ConversationRetriever returns relevant results
- [ ] Hierarchical search works (conversations → exchanges)
- [ ] RAG context appears in DocumentBuilder output
- [ ] fetch_conversation_details tool works for both conversation_id and exchange_id
- [ ] Graceful degradation (no crash if RAG fails)
- [ ] All existing tests pass

### Manual Testing

```bash
# Create conversations with summaries and embeddings
application.start_conversation_summarizer_worker
application.start_exchange_summarizer_worker
application.start_embedding_pipeline_worker

# Create test conversations
# ... have some conversations about "timeout bug" ...

# Start new conversation
# Ask: "How did we fix the timeout issue?"

# Verify:
# 1. RAG context appears with relevant past conversations
# 2. LLM can call fetch_conversation_details(conversation_id: X)
# 3. Tool returns detailed information

# Test with RAG disabled
# /rag off
# Ask same question
# Verify: No RAG context, system still works
```

### Git Commits

```bash
# Commit 1: Context processors
git add lib/nu/agent/context_processors/
git commit -m "Add Chain of Responsibility pattern for RAG pipeline

- Create base ContextProcessor with chain support
- Implement QueryEmbeddingProcessor
- Implement ConversationSearchProcessor
- Implement ExchangeSearchProcessor
- Implement ContextFormatterProcessor

Enables configurable, testable RAG processing pipeline."

# Commit 2: RAG integration
git add lib/nu/agent/conversation_retriever.rb lib/nu/agent/chat_loop_orchestrator.rb lib/nu/agent/document_builder.rb
git commit -m "Integrate RAG retrieval into chat loop

- Create ConversationRetriever to coordinate pipeline
- Update ChatLoopOrchestrator to retrieve RAG context
- Update DocumentBuilder to format RAG section with metadata
- Add graceful degradation for RAG failures

RAG now automatically injects relevant past conversations."

# Commit 3: fetch_conversation_details tool
git add lib/nu/agent/tools/fetch_conversation_details.rb
git commit -m "Add fetch_conversation_details tool for LLM-driven retrieval

- Tool accepts conversation_id or exchange_id
- Returns detailed information with optional full transcript
- Enables two-tier RAG: automatic summaries + on-demand details

LLM can now drill into specific past conversations."
```

---

## Phase 5: Command Interface

**Estimated time:** 1.5 hours
**Priority:** MEDIUM

### Goal

Implement command interface for controlling summarizers, embeddings, and RAG configuration. Add auto-start based on ConfigStore.

### Tasks

#### 1. Update /summarizer Command

Modify existing `SummarizerCommand` to support exchange summarizer:

```ruby
module Nu
  module Agent
    module Commands
      class SummarizerCommand < BaseCommand
        def execute(args)
          case args.first
          when 'on'
            start_all_summarizers
          when 'off'
            stop_all_summarizers
          when 'conversation'
            handle_conversation_command(args[1])
          when 'exchange'
            handle_exchange_command(args[1])
          when nil
            show_all_status
          else
            show_help
          end
        end

        private

        def start_all_summarizers
          @application.start_conversation_summarizer_worker
          @application.start_exchange_summarizer_worker
          @application.start_embedding_pipeline_worker

          @config_store.set('summarizer_conversation_enabled', true)
          @config_store.set('summarizer_exchange_enabled', true)
          @config_store.set('embedding_pipeline_enabled', true)

          @output_line.call("All summarizers and embedding pipeline started.")
        end

        def stop_all_summarizers
          @application.stop_conversation_summarizer_worker
          @application.stop_exchange_summarizer_worker
          @application.stop_embedding_pipeline_worker

          @config_store.set('summarizer_conversation_enabled', false)
          @config_store.set('summarizer_exchange_enabled', false)
          @config_store.set('embedding_pipeline_enabled', false)

          @output_line.call("All summarizers and embedding pipeline stopped.")
        end

        def handle_conversation_command(action)
          case action
          when 'on'
            @application.start_conversation_summarizer_worker
            @config_store.set('summarizer_conversation_enabled', true)
            @output_line.call("Conversation summarizer started.")
          when 'off'
            @application.stop_conversation_summarizer_worker
            @config_store.set('summarizer_conversation_enabled', false)
            @output_line.call("Conversation summarizer stopped.")
          when nil
            show_conversation_status
          else
            show_help
          end
        end

        def handle_exchange_command(action)
          case action
          when 'on'
            @application.start_exchange_summarizer_worker
            @config_store.set('summarizer_exchange_enabled', true)
            @output_line.call("Exchange summarizer started.")
          when 'off'
            @application.stop_exchange_summarizer_worker
            @config_store.set('summarizer_exchange_enabled', false)
            @output_line.call("Exchange summarizer stopped.")
          when nil
            show_exchange_status
          else
            show_help
          end
        end

        def show_all_status
          conv_status = @application.conversation_summarizer_status.call
          exch_status = @application.exchange_summarizer_status.call

          @output_line.call("Conversation Summarizer: #{format_status(conv_status)}")
          @output_line.call("Exchange Summarizer: #{format_status(exch_status)}")
          @output_line.call("\nEmbedding Pipeline: RUNNING (see /embeddings for details)")
        end

        def format_status(status)
          case status[:state]
          when 'idle'
            "IDLE - Completed: #{status[:completed]}, Failed: #{status[:failed]}"
          when /^running/
            "RUNNING - #{status[:state]}, Completed: #{status[:completed]}, Failed: #{status[:failed]}"
          else
            "STOPPED"
          end
        end
      end
    end
  end
end
```

#### 2. Create /embeddings Command

Create `lib/nu/agent/commands/embeddings_command.rb`:

```ruby
module Nu
  module Agent
    module Commands
      class EmbeddingsCommand < BaseCommand
        def execute(args)
          case args.first
          when 'on'
            start_embedding_pipeline
          when 'off'
            stop_embedding_pipeline
          when 'rebuild'
            rebuild_embeddings(args[1])
          when nil
            show_status
          else
            show_help
          end
        end

        private

        def start_embedding_pipeline
          @application.start_embedding_pipeline_worker
          @config_store.set('embedding_pipeline_enabled', true)
          @output_line.call("Embedding pipeline started.")
        end

        def stop_embedding_pipeline
          @application.stop_embedding_pipeline_worker
          @config_store.set('embedding_pipeline_enabled', false)
          @output_line.call("Embedding pipeline stopped.")
        end

        def show_status
          status = @application.embedding_pipeline_status.call

          @output_line.call("Embedding Pipeline: #{format_state(status)}")

          if status[:state] != 'stopped'
            @output_line.call("  Completed: #{status[:completed]}, Failed: #{status[:failed]}")
            @output_line.call("  Retry queue: #{status[:retry_queue_size]} items") if status[:retry_queue_size] > 0
          end

          show_embedding_counts
        end

        def show_embedding_counts
          result = @history.connection.query(<<~SQL)
            SELECT kind, COUNT(*) as count
            FROM text_embedding_3_small
            GROUP BY kind
          SQL

          @output_line.call("\nEmbedding counts:")
          result.each do |row|
            @output_line.call("  - #{row[0]}: #{row[1]}")
          end
        end

        def rebuild_embeddings(kind)
          @output_line.call("⚠️  WARNING: This will delete and recreate embeddings.")
          @output_line.call("Type 'yes' to confirm:")

          # TODO: Read confirmation from console
          # For now, just show what would happen
          @output_line.call("Rebuild cancelled (confirmation required).")
        end

        def format_state(status)
          case status[:state]
          when 'idle'
            'IDLE'
          when /^running/
            "RUNNING - #{status[:state]}"
          else
            'STOPPED'
          end
        end
      end
    end
  end
end
```

Register in `CommandRegistry`:

```ruby
register_command(Commands::EmbeddingsCommand.new(...))
```

#### 3. Create /rag Command

Create `lib/nu/agent/commands/rag_command.rb`:

```ruby
module Nu
  module Agent
    module Commands
      class RagCommand < BaseCommand
        def execute(args)
          case args.first
          when 'on'
            enable_rag
          when 'off'
            disable_rag
          when 'config'
            show_config
          when 'set'
            set_config(args[1], args[2])
          when nil
            show_status
          else
            show_help
          end
        end

        private

        def enable_rag
          @config_store.set('rag_enabled', true)
          @output_line.call("RAG enabled.")
        end

        def disable_rag
          @config_store.set('rag_enabled', false)
          @output_line.call("RAG disabled.")
        end

        def show_status
          enabled = @config_store.get('rag_enabled', true)
          @output_line.call("RAG Status: #{enabled ? 'ENABLED' : 'DISABLED'}")

          show_embedding_counts
          show_config_summary
        end

        def show_config
          config_keys = [
            'rag_enabled',
            'rag_conversation_limit',
            'rag_exchange_limit_per_conversation',
            'rag_min_similarity'
          ]

          @output_line.call("RAG Configuration:")
          config_keys.each do |key|
            value = @config_store.get(key)
            @output_line.call("  #{key}: #{value}")
          end

          @output_line.call("\nTo update: /rag set <key> <value>")
        end

        def set_config(key, value)
          return @output_line.call("Usage: /rag set <key> <value>") if key.nil? || value.nil?

          # Validate key
          valid_keys = ['rag_conversation_limit', 'rag_exchange_limit_per_conversation', 'rag_min_similarity']
          return @output_line.call("Invalid key. Valid keys: #{valid_keys.join(', ')}") unless valid_keys.include?(key)

          # Parse and validate value
          parsed_value = case key
          when /limit/
            Integer(value)
          when /similarity/
            Float(value)
          end

          # Validate ranges
          if key.include?('limit') && parsed_value <= 0
            return @output_line.call("Limit must be greater than 0")
          end

          if key.include?('similarity') && (parsed_value < 0 || parsed_value > 1)
            return @output_line.call("Similarity must be between 0 and 1")
          end

          @config_store.set(key, parsed_value)
          @output_line.call("Updated: #{key} = #{parsed_value}")
        rescue ArgumentError
          @output_line.call("Invalid value for #{key}")
        end

        def show_embedding_counts
          result = @history.connection.query(<<~SQL)
            SELECT kind, COUNT(*) as count
            FROM text_embedding_3_small
            GROUP BY kind
          SQL

          @output_line.call("\nEmbeddings:")
          result.each do |row|
            @output_line.call("  - #{row[0]}: #{row[1]}")
          end
        end

        def show_config_summary
          limit = @config_store.get('rag_conversation_limit', 3)
          per_conv = @config_store.get('rag_exchange_limit_per_conversation', 2)
          min_sim = @config_store.get('rag_min_similarity', 0.7)

          @output_line.call("\nConfiguration:")
          @output_line.call("  - Conversation retrieval limit: #{limit}")
          @output_line.call("  - Exchange limit per conversation: #{per_conv}")
          @output_line.call("  - Minimum similarity threshold: #{min_sim}")
        end
      end
    end
  end
end
```

Register in `CommandRegistry`:

```ruby
register_command(Commands::RagCommand.new(...))
```

#### 4. Add Auto-Start to Application

```ruby
def initialize
  # ... existing setup ...
  auto_start_background_workers
end

private

def auto_start_background_workers
  config = @config_store.get_all

  start_conversation_summarizer_worker if config['summarizer_conversation_enabled']
  start_exchange_summarizer_worker if config['summarizer_exchange_enabled']
  start_embedding_pipeline_worker if config['embedding_pipeline_enabled']
end
```

#### 5. Add Default Configuration in SchemaManager

```ruby
def initialize_default_config
  defaults = {
    'rag_enabled' => true,
    'rag_conversation_limit' => 3,
    'rag_exchange_limit_per_conversation' => 2,
    'rag_min_similarity' => 0.7,
    'summarizer_conversation_enabled' => true,
    'summarizer_exchange_enabled' => true,
    'embedding_pipeline_enabled' => true,
    'summarizer_idle_timeout' => 30,
    'embedding_pipeline_poll_interval' => 5,
    'embedding_batch_size' => 100,
    'embedding_max_retries' => 6
  }

  defaults.each do |key, value|
    @config_store.set(key, value) unless @config_store.exists?(key)
  end
end
```

Call during `setup_database()`.

### Validation Checklist

- [ ] All command variations work (/summarizer, /embeddings, /rag)
- [ ] Workers auto-start based on ConfigStore
- [ ] Status output is accurate
- [ ] Configuration changes persist across restarts
- [ ] All existing tests pass

### Manual Testing

```bash
# Test auto-start
# Quit and restart application
# Verify workers start automatically

# Test commands
/summarizer
/summarizer on
/summarizer off
/summarizer conversation
/summarizer exchange

/embeddings
/embeddings on
/embeddings off

/rag
/rag on
/rag off
/rag config
/rag set rag_conversation_limit 5

# Quit and restart, verify config persists
```

### Git Commit

```bash
git add -A
git commit -m "Add command interface for summarizers, embeddings, and RAG

- Update /summarizer command to support exchange summarizer
- Create /embeddings command with status and rebuild
- Create /rag command for configuration
- Add auto-start based on ConfigStore
- Initialize default configuration in SchemaManager

Commands persist state across sessions via ConfigStore."
```

---

## Phase 6: Testing & Documentation

**Estimated time:** 1 hour
**Priority:** MEDIUM

### Goal

Integration testing, documentation updates, and final validation.

### Tasks

#### 1. Integration Tests

Create `spec/nu/agent/rag_integration_spec.rb`:

```ruby
RSpec.describe 'RAG Integration' do
  it 'end-to-end: create conversation, summarize, embed, query with RAG' do
    # 1. Create conversation with exchanges
    # 2. Wait for summarization
    # 3. Wait for embedding
    # 4. Start new conversation
    # 5. Query similar to first conversation
    # 6. Verify RAG context appears
    # 7. Verify LLM can call fetch_conversation_details
  end

  it 'retrieves similar conversations' do
    # Test ConversationRetriever
  end

  it 'excludes current conversation from RAG' do
    # Test exclusion logic
  end

  it 'respects similarity threshold' do
    # Test min_similarity filtering
  end

  it 'gracefully degrades when RAG disabled' do
    # Test /rag off
  end
end
```

#### 2. Update README

Add RAG section:

```markdown
## RAG: Conversational Memory

Nu-Agent implements Retrieval-Augmented Generation (RAG) to remember and reference past conversations.

### How It Works

1. **Summarization** - Completed exchanges and conversations are automatically summarized in the background
2. **Embedding** - Summaries are embedded as 1536-dimensional vectors using OpenAI's text-embedding-3-small
3. **Retrieval** - When you ask a question, the agent searches for similar past conversations and includes them in the context

### Commands

- `/summarizer` - Control conversation and exchange summarization
- `/embeddings` - Manage embedding pipeline
- `/rag` - Configure RAG system

### Configuration

RAG is enabled by default. Configure via `/rag set`:

- `rag_conversation_limit` - Number of similar conversations to retrieve (default: 3)
- `rag_exchange_limit_per_conversation` - Number of exchanges per conversation (default: 2)
- `rag_min_similarity` - Minimum similarity threshold (default: 0.7)

### Cost

- Summarization: ~$0.001-0.005 per conversation
- Embeddings: ~$0.000002 per summary (effectively free)
- Retrieval: ~$0.000002 per query
```

#### 3. Update architecture-analysis.md

Add RAG section:

```markdown
## RAG System (Added in v0.11)

### Architecture

```
User Query → RAG Pipeline (Chain of Responsibility) → LLM
  ↓
  1. Query Embedding
  2. Conversation Search
  3. Exchange Search
  4. Context Formatting
```

### Components

- **ExchangeSummarizer**: Background worker for exchange-level summarization
- **EmbeddingPipeline**: Background worker with batching and retry logic
- **ConversationRetriever**: Coordinates RAG pipeline
- **Context Processors**: Chain of Responsibility pattern for processing stages
- **fetch_conversation_details**: Tool for LLM-driven retrieval

### Patterns

- ✅ **Chain of Responsibility**: RAG processing pipeline
- ✅ **Background Worker**: Async summarization and embedding
- ✅ **Graceful Degradation**: System continues if RAG fails
```

#### 4. Create docs/rag-architecture.md

Diagram showing:
- Three workers (ConversationSummarizer, ExchangeSummarizer, EmbeddingPipeline)
- RAG pipeline (Chain of Responsibility)
- Data flow
- Integration points

#### 5. Performance Testing

```bash
# Test with 100 conversations
# Measure RAG retrieval latency
# Verify < 500ms

# Test with 1000 embeddings
# Verify HNSW index performance
```

### Validation Checklist

- [ ] All integration tests pass
- [ ] Unit tests for all new classes
- [ ] RAG retrieval works in real usage
- [ ] Performance < 500ms for retrieval
- [ ] Documentation is clear and complete
- [ ] All manual test scenarios pass

### Git Commit

```bash
git add -A
git commit -m "Add integration tests and documentation for RAG system

- Create RAG integration test suite
- Update README with RAG section
- Update architecture-analysis.md with RAG patterns
- Create rag-architecture.md diagram
- Add performance validation

RAG system is now fully documented and tested."
```

---

## Testing Strategy

### Unit Tests

Create test files for each new class:

- `spec/nu/agent/exchange_summarizer_spec.rb`
- `spec/nu/agent/embedding_pipeline_spec.rb`
- `spec/nu/agent/conversation_retriever_spec.rb`
- `spec/nu/agent/context_processors/context_processor_spec.rb`
- `spec/nu/agent/context_processors/query_embedding_processor_spec.rb`
- `spec/nu/agent/context_processors/conversation_search_processor_spec.rb`
- `spec/nu/agent/context_processors/exchange_search_processor_spec.rb`
- `spec/nu/agent/context_processors/context_formatter_processor_spec.rb`
- `spec/nu/agent/tools/fetch_conversation_details_spec.rb`
- `spec/nu/agent/commands/embeddings_command_spec.rb`
- `spec/nu/agent/commands/rag_command_spec.rb`

### Integration Tests

- End-to-end RAG flow
- Worker coordination
- Command interface
- Error handling

### Mocking Strategy

- Mock OpenAI API calls (embeddings_client)
- Use real DuckDB in-memory database for tests
- Mock Application#output_line (avoid test output)

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific phase tests
bundle exec rspec spec/nu/agent/exchange_summarizer_spec.rb
bundle exec rspec spec/nu/agent/embedding_pipeline_spec.rb
bundle exec rspec spec/nu/agent/rag_integration_spec.rb

# Run with coverage
COVERAGE=true bundle exec rspec
```

### Manual Testing Checklist

**Phase 0:**
- [ ] Man-page code deleted, tests pass, no man_page embeddings

**Phase 1:**
- [ ] VSS extension loads
- [ ] HNSW index created
- [ ] Similarity search works

**Phase 2:**
- [ ] ExchangeSummarizer finds and summarizes exchanges
- [ ] Summaries stored in database
- [ ] Worker goes idle when no work

**Phase 3:**
- [ ] EmbeddingPipeline finds summaries without embeddings
- [ ] Batches multiple embeddings per API call
- [ ] Retry queue handles failures

**Phase 4:**
- [ ] RAG context appears for similar queries
- [ ] LLM can call fetch_conversation_details
- [ ] Chain of Responsibility pattern works

**Phase 5:**
- [ ] All commands work (/summarizer, /embeddings, /rag)
- [ ] Workers auto-start on launch
- [ ] Configuration persists

**Phase 6:**
- [ ] All integration tests pass
- [ ] RAG retrieval < 500ms
- [ ] Documentation complete

---

## Configuration Reference

### ConfigStore Keys

All RAG-related configuration stored in `appconfig` table:

```ruby
{
  # RAG retrieval
  "rag_enabled" => true,                              # Master toggle
  "rag_conversation_limit" => 3,                      # Top N conversations
  "rag_exchange_limit_per_conversation" => 2,         # Top M exchanges per conversation
  "rag_min_similarity" => 0.7,                        # Minimum cosine similarity (0-1)

  # Worker lifecycle (auto-start)
  "summarizer_conversation_enabled" => true,          # Auto-start conversation summarizer
  "summarizer_exchange_enabled" => true,              # Auto-start exchange summarizer
  "embedding_pipeline_enabled" => true,               # Auto-start embedding pipeline

  # Worker behavior
  "summarizer_idle_timeout" => 30,                    # Seconds to sleep when idle
  "embedding_pipeline_poll_interval" => 5,            # Seconds between polls
  "embedding_batch_size" => 100,                      # Max embeddings per API call
  "embedding_max_retries" => 6                        # Max retry attempts
}
```

### Configuration via Commands

```bash
# RAG configuration
/rag set rag_conversation_limit 5
/rag set rag_exchange_limit_per_conversation 3
/rag set rag_min_similarity 0.8

# Enable/disable
/rag on
/rag off

# Workers
/summarizer on
/summarizer off
/summarizer conversation on
/summarizer exchange off

/embeddings on
/embeddings off
```

### Database Schema

**New columns:**
- `text_embedding_3_small.conversation_id` (foreign key)
- `text_embedding_3_small.exchange_id` (foreign key)

**New indexes:**
- `idx_embedding_conversation` (on conversation_id)
- `idx_embedding_exchange` (on exchange_id)
- `embedding_hnsw_idx` (HNSW on embedding vector)

---

## Success Criteria

### Phase Completion

**Phase 0:**
- [ ] All man-page code deleted
- [ ] All tests pass
- [ ] No man_page embeddings in database

**Phase 1:**
- [ ] VSS extension loads without error
- [ ] HNSW index created
- [ ] Similarity search returns ordered results

**Phase 2:**
- [ ] ExchangeSummarizer finds and summarizes exchanges
- [ ] Summaries stored in exchanges.summary column
- [ ] Worker excludes current conversation
- [ ] Signals embedding pipeline

**Phase 3:**
- [ ] EmbeddingPipeline finds summaries without embeddings
- [ ] Batches multiple embeddings per API call
- [ ] Stores embeddings with correct foreign keys
- [ ] Retry queue handles failures

**Phase 4:**
- [ ] Chain of Responsibility pattern implemented
- [ ] ConversationRetriever returns relevant results
- [ ] RAG context appears in DocumentBuilder output
- [ ] fetch_conversation_details tool works

**Phase 5:**
- [ ] All command variations work
- [ ] Workers auto-start based on ConfigStore
- [ ] Configuration changes persist

**Phase 6:**
- [ ] All integration tests pass
- [ ] RAG retrieval latency < 500ms
- [ ] Documentation updated

### Overall Success

- [ ] Agent can reference past conversations in responses
- [ ] Users experience improved context continuity
- [ ] System is stable (no crashes, no data loss)
- [ ] Performance is acceptable (retrieval < 500ms)
- [ ] Costs are reasonable (< $0.01 per query)

---

## Deferred Improvements (v0.12+)

The following improvements from `plan-0.11.md` are deferred to v0.12 or later:

### 1. Complete Application Class Refactoring

**Current State:** 287 lines (down 43% from 500+)
**Target:** < 150 lines

**Extract:**
- SystemLifecycle (shutdown, signals, critical sections)
- ConversationCoordinator (high-level conversation flow)

**Priority:** LOW (Application is acceptable for current scale)

### 2. Event-Based Message Display

**Current State:** Polling every 100ms
**Target:** Event-driven with MessageBus

**Benefits:**
- Eliminate polling overhead
- Reduce latency to < 10ms
- Easier to add observers

**Priority:** LOW (Performance optimization, not required for RAG)

### 3. State Pattern in ConsoleIO

**Current State:** 626 lines with boolean flags
**Target:** Explicit State classes

**Benefits:**
- Clearer state transitions
- Reduced conditional complexity

**Priority:** LOW (Internal refactoring, unrelated to RAG)

### 4. Tool Decorators

**Current State:** Each tool implements own error handling
**Target:** Decorator pattern for cross-cutting concerns

**Benefits:**
- Consistent logging
- Permission checking
- Audit trail

**Priority:** LOW (Nice-to-have, not blocking)

---

## Notes for Future Sessions

### Session Continuity

Since you'll implement this across multiple sessions and lose context, follow these guidelines:

#### Before Starting a Phase

1. **Read phase description completely**
2. **Check prerequisites** (previous phases completed)
3. **Review validation checklist**
4. **Run existing tests** to establish baseline

#### During Implementation

1. **Commit frequently** - After each logical unit of work
2. **Run tests frequently** - After each change
3. **Update checklists** - Mark items as complete
4. **Document issues** - Note any problems encountered

#### After Completing a Phase

1. **Run full test suite** - Verify no regressions
2. **Manual testing** - Follow validation checklist
3. **Git commit** - Use commit message template from phase
4. **Update this document** - Mark phase as complete

### Finding Your Place

If you lose context mid-phase:

1. **Check git log** - See what's been committed
2. **Review test results** - What's passing/failing?
3. **Read validation checklist** - What's complete?
4. **Grep for TODOs** - Find unfinished work

### Getting Help

If stuck:

1. **Re-read rag-implementation-plan.md** - Full design details
2. **Check architecture-analysis.md** - Patterns and examples
3. **Review similar code** - ConversationSummarizer is example for ExchangeSummarizer
4. **Run tests** - They document expected behavior

### Common Pitfalls

- **Forgetting to signal workers** - Each worker needs signals from upstream
- **Foreign key mismatches** - conversation_id vs exchange_id
- **Thread safety** - Always use enter/exit_critical_section for writes
- **Graceful degradation** - Wrap RAG calls in begin/rescue
- **Testing with real API** - Mock OpenAI calls in tests

### Progress Tracking

Update this checklist as you complete phases:

- [ ] Phase 0: Man-Page Infrastructure Removal
- [ ] Phase 1: Database Schema Changes
- [ ] Phase 2: ExchangeSummarizer Worker
- [ ] Phase 3: EmbeddingPipeline Worker
- [ ] Phase 4: RAG Integration with Chain of Responsibility
- [ ] Phase 5: Command Interface
- [ ] Phase 6: Testing & Documentation

**When all phases complete, bump version to 0.11.0 and close issue #17.**

---

**End of Plan**

This plan provides everything needed to implement RAG with Chain of Responsibility pattern across multiple sessions. Each phase is self-contained with clear validation criteria and git commit messages.
