# RAG Implementation Plan: Conversational Memory

**Version:** 1.0 (Draft)
**Created:** 2025-10-28
**Status:** Planning - Awaiting refinement
**GitHub Issue:** #17

---

## Executive Summary

### What
Implement Retrieval-Augmented Generation (RAG) to give the agent **conversational memory** - the ability to learn from and reference past interactions across conversations.

### Why
- **Knowledge retention:** Agent remembers solutions, decisions, and patterns from past work
- **Context continuity:** Can reference "how we did X before"
- **Improved responses:** Leverages historical context for better answers
- **Learning over time:** Agent becomes more useful as conversation history grows

### Impact
The agent will automatically retrieve and reference relevant past conversations and exchanges when responding to new queries, creating a sense of continuity and accumulated knowledge.

### Scope
Replace man-page indexing with a three-tier system:
1. **Exchange summarization** - Summarize each completed exchange
2. **Embedding pipeline** - Generate vector embeddings for all summaries
3. **RAG retrieval** - Automatically retrieve relevant past context during queries

---

## Current State & Gap Analysis

### What Exists ✅

**Infrastructure:**
- `text_embedding_3_small` table in DuckDB for vector storage
- `EmbeddingStore` class for managing embeddings
- `OpenAIEmbeddings` client (text-embedding-3-small model)
- `ConversationSummarizer` background worker
- `BackgroundWorkerManager` for thread lifecycle
- `conversations.summary` and `exchanges.summary` columns in schema

**Architecture:**
- Transaction support via `History` facade
- Per-thread DuckDB connections
- Background worker patterns with status tracking
- Critical section management for database writes

### What's Missing ❌

**Workers:**
- ❌ `ExchangeSummarizer` - No exchange-level summarization (only conversations)
- ❌ `EmbeddingPipeline` - No automatic embedding generation
- ❌ Exchange summaries are never populated

**RAG System:**
- ❌ Vector similarity search (DuckDB VSS extension not enabled)
- ❌ HNSW index on embeddings
- ❌ `ConversationRetriever` for semantic search
- ❌ Integration with `ChatLoopOrchestrator`
- ❌ RAG context formatting in `DocumentBuilder`

**Commands:**
- ❌ `/summarizer exchange` commands
- ❌ `/embeddings` command
- ❌ `/rag` configuration command
- ❌ Tools for LLM to fetch conversation details

**Database:**
- ❌ VSS extension not installed/loaded
- ❌ No HNSW index on embedding column
- ❌ No foreign keys linking embeddings to conversations/exchanges
- ❌ Man-page embeddings still present (need cleanup)

### Man-Page Removal Rationale

**Current man-page indexing:**
- Indexes system man pages for semantic search
- Less valuable than conversational memory
- Adds complexity and maintenance burden
- Uses embedding storage that could be for conversations

**Decision:** Remove man-page infrastructure entirely before implementing conversational RAG.
- Cleaner foundation
- Frees up `kind='man_page'` namespace
- Reduces code complexity
- Man pages are available via other tools (bash `man` command)

---

## Architecture Overview

### Three-Worker System

```
┌─────────────────────────────────────────────────────────┐
│  USER QUERY                                             │
└────────────────────────┬────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│  RAG RETRIEVAL (Pre-LLM)                                │
│  1. Embed current user query                            │
│  2. Search similar CONVERSATION summaries (top 3-5)     │
│  3. Within those, search similar EXCHANGE summaries     │
│  4. Format retrieved context with metadata              │
└────────────────────────┬────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│  CONTEXT DOCUMENT                                       │
│  - Related conversations (titles + summaries + IDs)     │
│  - Related exchanges (from those conversations)         │
│  - Current conversation history                         │
│  - Available tools (including fetch_conversation_details)
│  - User query                                           │
└────────────────────────┬────────────────────────────────┘
                         ↓
                       LLM
                         ↓
                 (optional tool call)
                         ↓
┌─────────────────────────────────────────────────────────┐
│  FETCH_CONVERSATION_DETAILS TOOL                        │
│  LLM can request full details for specific conv/exchange│
│  Uses IDs from RAG metadata                             │
└─────────────────────────────────────────────────────────┘

BACKGROUND WORKERS (Async):

Worker 1: ConversationSummarizer (EXISTS - MODIFY)
  ├─> Monitors conversations WHERE summary IS NULL
  ├─> Excludes current conversation
  ├─> Generates 2-3 sentence summaries
  ├─> Signals EmbeddingPipeline when done
  └─> Continuous daemon mode

Worker 2: ExchangeSummarizer (NEW)
  ├─> Monitors exchanges WHERE summary IS NULL
  ├─> Excludes current conversation's exchanges
  ├─> Generates 1-2 sentence summaries
  ├─> Signals EmbeddingPipeline when done
  └─> Continuous daemon mode

Worker 3: EmbeddingPipeline (NEW)
  ├─> Monitors conversations/exchanges with summary but no embedding
  ├─> Batch embeds (up to 100 at a time)
  ├─> Stores with foreign keys (conversation_id/exchange_id)
  ├─> Exponential backoff on API failures
  └─> Continuous daemon mode
```

### Data Flow

```
Exchange completes
    ↓
ExchangeSummarizer picks it up
    ↓
Summary generated and stored
    ↓
Signal sent to EmbeddingPipeline
    ↓
EmbeddingPipeline embeds summary (within 1-5 seconds)
    ↓
Embedding stored with foreign key
    ↓
Now available for RAG retrieval

(Same flow for conversations)
```

### Hierarchical Retrieval Strategy

```
User query: "How did we fix the timeout issue?"
    ↓
Embed query → [0.123, 0.456, ..., 0.789] (1536-dim vector)
    ↓
Search conversation summaries (cosine similarity)
    ↓
Top 3 conversations:
  - "Debug connection timeouts" (ID: 123, similarity: 0.87)
  - "Retry logic implementation" (ID: 156, similarity: 0.73)
  - "Socket configuration" (ID: 89, similarity: 0.71)
    ↓
Within those 3 conversations, search exchange summaries
    ↓
Top 2 exchanges per conversation:
  - Conv 123, Exchange 456: "Identified default timeout was too short" (0.91)
  - Conv 123, Exchange 457: "Increased socket timeout to 120s" (0.88)
  - Conv 156, Exchange 789: "Added exponential backoff logic" (0.79)
  - ...
    ↓
Format as RAG context with metadata (IDs, dates, similarity scores)
    ↓
Inject into LLM context
    ↓
LLM sees metadata, can call fetch_conversation_details(conversation_id: 123)
```

---

## Database Schema Changes

### 1. Enable VSS Extension

DuckDB 1.4.1+ includes the Vector Similarity Search (VSS) extension.

```ruby
# In SchemaManager#setup_database
def enable_vss_extension
  @connection.query("INSTALL vss")
  @connection.query("LOAD vss")
end
```

**When to run:** Once during Phase 1, persists across sessions.

### 2. Add Foreign Keys to Embeddings Table

**Current schema:**
```sql
CREATE TABLE IF NOT EXISTS text_embedding_3_small (
  id INTEGER PRIMARY KEY DEFAULT nextval('text_embedding_3_small_id_seq'),
  kind TEXT NOT NULL,              -- "conversation_summary", "exchange_summary", "man_page"
  source TEXT NOT NULL,            -- "conversation_123", "exchange_456"
  content TEXT NOT NULL,           -- The actual summary text
  embedding FLOAT[1536],           -- OpenAI text-embedding-3-small
  indexed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(kind, source)
)
```

**New schema:**
```sql
-- Add foreign key columns
ALTER TABLE text_embedding_3_small
  ADD COLUMN conversation_id INTEGER REFERENCES conversations(id);

ALTER TABLE text_embedding_3_small
  ADD COLUMN exchange_id INTEGER REFERENCES exchanges(id);

-- Add indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_embedding_conversation
  ON text_embedding_3_small(conversation_id);

CREATE INDEX IF NOT EXISTS idx_embedding_exchange
  ON text_embedding_3_small(exchange_id);
```

**Migration strategy for existing embeddings:**
- Option A: Parse `source` string ("conversation_123" → 123) and backfill
- Option B: Delete all embeddings and rebuild from summaries
- Option C: Leave old records, only new embeddings use foreign keys

**Recommendation:** Option B - Clean slate. Man-pages will be deleted anyway.

### 3. Create HNSW Index for Vector Similarity

```sql
-- Create HNSW index on embedding column
CREATE INDEX IF NOT EXISTS embedding_hnsw_idx
  ON text_embedding_3_small
  USING HNSW (embedding);
```

**What is HNSW?**
- Hierarchical Navigable Small Worlds
- Approximate nearest neighbor search
- Fast similarity queries on high-dimensional vectors
- Index lives in RAM, persisted to disk with database

**Performance:**
- Without index: O(N) linear scan (slow for 1000+ embeddings)
- With HNSW: O(log N) approximate search (fast even for millions)

### 4. Clean Up Man-Page Embeddings

```sql
-- Delete all man-page embeddings
DELETE FROM text_embedding_3_small WHERE kind = 'man_page';
```

**When to run:** During Phase 0 (man-page removal).

---

## Worker Specifications

### Worker 1: ConversationSummarizer (Modify Existing)

**Current behavior:**
- One-shot batch mode (start, process all, stop)
- Triggered via `/summarizer start` command
- Processes unsummarized conversations
- Excludes current conversation

**New behavior:**
- **Continuous daemon mode** - Runs until explicitly stopped
- **Idle state** - Sleeps when no work, wakes on signal or timeout
- **Auto-start** - Restarts based on ConfigStore state across sessions
- **Signals embedding pipeline** when summaries are created

**State machine:**
```
STOPPED → START → RUNNING → [IDLE ⇄ PROCESSING] → STOPPED
```

**Pseudo-code:**
```ruby
class ConversationSummarizer
  def run_continuously
    loop do
      break if @shutdown

      conversations = find_unsummarized_conversations()

      if conversations.empty?
        set_status_idle()
        wait_for_signal_or_timeout(30) # 30 sec idle timeout
        next
      end

      set_status_running(conversations.length)

      conversations.each do |conv|
        break if @shutdown
        process_conversation(conv)
        signal_embedding_pipeline() # NEW
      end
    end
  end

  def wait_for_signal_or_timeout(seconds)
    @mutex.synchronize do
      @condition_variable.wait(@mutex, seconds)
    end
  end

  def signal
    @mutex.synchronize { @condition_variable.signal }
  end
end
```

**When to signal:**
- After each new conversation is created
- When user runs `/summarizer conversation on`
- When background worker is idle and new conversation appears

### Worker 2: ExchangeSummarizer (New)

**Purpose:** Summarize individual exchanges (user-assistant interaction pairs).

**Behavior:**
- Continuous daemon mode
- Finds exchanges WHERE `summary IS NULL AND status = 'completed'`
- Excludes exchanges from current conversation
- Orders by `completed_at DESC` (newest first)
- Generates 1-2 sentence summaries
- Signals embedding pipeline after each summary

**Query:**
```sql
SELECT * FROM exchanges
WHERE summary IS NULL
  AND status = 'completed'
  AND conversation_id != ?  -- Exclude current conversation
ORDER BY completed_at DESC
LIMIT 100
```

**Prompt template:**
```ruby
def build_summary_prompt(exchange)
  <<~PROMPT
    Summarize this exchange concisely in 1-2 sentences.
    Focus on: what the user asked, what action was taken, and the outcome.

    User: #{exchange['user_message']}
    Assistant: #{exchange['assistant_message']}

    Summary:
  PROMPT
end
```

**State machine:** Same as ConversationSummarizer (STOPPED → RUNNING → IDLE/PROCESSING → STOPPED)

**Implementation:** Nearly identical to ConversationSummarizer, just different queries and prompts.

### Worker 3: EmbeddingPipeline (New)

**Purpose:** Generate and store embeddings for all summaries.

**Behavior:**
- Continuous daemon mode
- Finds summaries without embeddings:
  ```sql
  -- Conversations needing embeddings
  SELECT c.* FROM conversations c
  LEFT JOIN text_embedding_3_small e
    ON e.conversation_id = c.id AND e.kind = 'conversation_summary'
  WHERE c.summary IS NOT NULL
    AND e.id IS NULL

  -- Exchanges needing embeddings
  SELECT e.* FROM exchanges e
  LEFT JOIN text_embedding_3_small emb
    ON emb.exchange_id = e.id AND emb.kind = 'exchange_summary'
  WHERE e.summary IS NOT NULL
    AND emb.id IS NULL
  ```
- Batch embeds (up to 100 items per API call)
- Stores embeddings atomically (entire batch or none)
- Exponential backoff on failures (1s, 2s, 4s, 8s, 16s, 32s, give up)
- Signals: Both signal + 5-second fallback poll

**Pseudo-code:**
```ruby
class EmbeddingPipeline
  def run_continuously
    loop do
      break if @shutdown

      # Find work
      conversations = find_conversations_needing_embeddings(limit: 100)
      exchanges = find_exchanges_needing_embeddings(limit: 100)
      retries = get_items_ready_for_retry() # Exponential backoff queue

      all_items = conversations + exchanges + retries

      if all_items.empty?
        set_status_idle()
        wait_for_signal_or_timeout(5) # Fast poll - 5 seconds
        next
      end

      set_status_running(all_items.length)
      process_batch_with_retry(all_items)
    end
  end

  def process_batch_with_retry(items)
    texts = items.map(&:summary)

    begin
      embeddings = @embeddings_client.embed_batch(texts) # OpenAI API call
      store_embeddings_atomically(items, embeddings)
      remove_from_retry_queue(items)
      increment_completed_count(items.length)
    rescue EmbeddingError => e
      handle_failure_with_backoff(items, e)
    end
  end

  def handle_failure_with_backoff(items, error)
    items.each do |item|
      attempts = @retry_queue[item.id]&.fetch(:attempts, 0) || 0
      next_retry = Time.now + (2 ** attempts) # 1s, 2s, 4s, 8s, 16s, 32s

      if attempts >= 6
        increment_failed_count()
        log_permanent_failure(item, error)
      else
        @retry_queue[item.id] = {
          attempts: attempts + 1,
          next_retry: next_retry,
          item: item,
          error: error.message
        }
      end
    end
  end

  def store_embeddings_atomically(items, embeddings)
    @application.send(:enter_critical_section)

    @history.transaction do
      items.zip(embeddings).each do |item, embedding|
        if item.is_a?(Conversation)
          @history.store_conversation_embedding(
            conversation_id: item.id,
            content: item.summary,
            embedding: embedding
          )
        elsif item.is_a?(Exchange)
          @history.store_exchange_embedding(
            exchange_id: item.id,
            content: item.summary,
            embedding: embedding
          )
        end
      end
    end
  ensure
    @application.send(:exit_critical_section)
  end
end
```

**API Efficiency:**
- OpenAI embeddings API supports batching up to 2048 texts per request
- Batching 100 summaries: 1 API call vs 100 individual calls
- Lower latency, lower cost, fewer rate limit issues

### Signaling Mechanism

**Decision:** Signal both workers independently.
**Rationale:** Simpler, no coupling between workers, each can fail independently.

**Implementation:**
```ruby
# In BackgroundWorkerManager
def signal_exchange_summarizer
  @exchange_summarizer&.signal
end

def signal_embedding_pipeline
  @embedding_pipeline&.signal
end

# When exchange completes (in ChatLoopOrchestrator)
def complete_exchange(exchange_id)
  @history.complete_exchange(exchange_id: exchange_id, ...)
  @background_worker_manager.signal_exchange_summarizer()
  @background_worker_manager.signal_embedding_pipeline()
end
```

---

## RAG Retrieval System

### ConversationRetriever

**Purpose:** Given a user query, retrieve relevant past conversations and exchanges.

**Strategy:** Hierarchical search
1. Embed the user query
2. Search conversation summaries (top N, e.g., 3-5)
3. Within those conversations, search exchange summaries (top M per conversation, e.g., 2)
4. Exclude current conversation
5. Filter by minimum similarity threshold (e.g., 0.7)
6. Return structured results with metadata

**Pseudo-code:**
```ruby
class ConversationRetriever
  def initialize(history:, embeddings_client:, config:)
    @history = history
    @embeddings_client = embeddings_client
    @config = config # From ConfigStore
  end

  def retrieve_related_context(query_text:, current_conversation_id:)
    # 1. Embed the query
    query_embedding = @embeddings_client.embed(query_text)

    # 2. Find similar conversations
    similar_convos = @history.search_similar_conversations(
      query_embedding: query_embedding,
      limit: @config.fetch('rag_conversation_limit', 3),
      min_similarity: @config.fetch('rag_min_similarity', 0.7),
      exclude_conversation_id: current_conversation_id
    )

    return nil if similar_convos.empty?

    # 3. Find similar exchanges within those conversations
    conversation_ids = similar_convos.map { |c| c[:conversation_id] }
    similar_exchanges = @history.search_similar_exchanges(
      query_embedding: query_embedding,
      conversation_ids: conversation_ids,
      limit_per_conversation: @config.fetch('rag_exchange_limit_per_conversation', 2),
      min_similarity: @config.fetch('rag_min_similarity', 0.7)
    )

    # 4. Enrich with conversation metadata
    format_rag_context(similar_convos, similar_exchanges)
  end

  private

  def format_rag_context(conversations, exchanges)
    {
      conversations: conversations.map { |c| enrich_conversation(c) },
      exchanges: exchanges.map { |e| enrich_exchange(e) }
    }
  end

  def enrich_conversation(conv_data)
    conv = @history.get_conversation(conv_data[:conversation_id])
    {
      id: conv['id'],
      title: conv['title'],
      summary: conv_data[:content], # The summary text
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
      user_message: exch['user_message'],
      assistant_message: exch['assistant_message'],
      completed_at: exch['completed_at']
    }
  end
end
```

### EmbeddingStore Similarity Search

**New methods:**
```ruby
class EmbeddingStore
  # Search conversation summaries by similarity
  def search_similar_conversations(query_embedding:, limit:, min_similarity:, exclude_conversation_id: nil)
    exclude_clause = exclude_conversation_id ?
      "AND conversation_id != #{exclude_conversation_id}" : ""

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

    result.map { |row|
      {
        conversation_id: row[0],
        content: row[1],
        similarity: row[2]
      }
    }
  end

  # Search exchange summaries within specific conversations
  def search_similar_exchanges(query_embedding:, conversation_ids:, limit_per_conversation:, min_similarity:)
    # Use window function to limit per conversation
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

    result.map { |row|
      {
        exchange_id: row[0],
        conversation_id: row[1],
        content: row[2],
        similarity: row[3]
      }
    }
  end

  private

  def format_embedding(embedding_array)
    "[#{embedding_array.join(', ')}]"
  end
end
```

**Note:** Uses `array_cosine_similarity()` function from DuckDB VSS extension.

---

## Integration with Chat Loop

### ChatLoopOrchestrator Changes

**Current flow:**
```
user_input → create_exchange → build_context → send_to_llm → tool_loop → complete_exchange
```

**New flow:**
```
user_input → create_exchange → retrieve_rag_context → build_context_with_rag → send_to_llm → tool_loop → complete_exchange
```

**Pseudo-code:**
```ruby
class ChatLoopOrchestrator
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

    # Signal workers
    @background_worker_manager.signal_exchange_summarizer()
    @background_worker_manager.signal_embedding_pipeline()
  end

  private

  def retrieve_rag_context_if_enabled(user_input)
    return nil unless rag_enabled?

    retriever = ConversationRetriever.new(
      history: @history,
      embeddings_client: @embeddings_client,
      config: load_rag_config()
    )

    retriever.retrieve_related_context(
      query_text: user_input,
      current_conversation_id: @conversation_id
    )
  rescue StandardError => e
    @application.output_line("[RAG] Retrieval failed: #{e.message}", type: :error)
    nil # Graceful degradation - continue without RAG
  end

  def rag_enabled?
    @config_store.get('rag_enabled', true)
  end
end
```

**Graceful degradation:** If RAG retrieval fails (embedding API down, database error), the system continues without RAG context.

### DocumentBuilder Changes

**Add RAG section to context document:**

```ruby
class DocumentBuilder
  def build(conversation_history:, tools:, user_query:, rag_context: nil)
    sections = []

    sections << build_system_section()
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
        - User: #{truncate(exch[:user_message], 200)}
        - Assistant: #{truncate(exch[:assistant_message], 200)}
      EXCH
    end.join("\n")
  end

  def truncate(text, length)
    return text if text.length <= length
    "#{text[0...length]}..."
  end
end
```

**Example output:**
```markdown
## Related Past Conversations

The following conversations and exchanges may be relevant to the current query.
You can use the `fetch_conversation_details` tool to get more information about any conversation or exchange using the IDs provided below.

### Conversation: "Debug connection timeouts" (ID: 123, Date: 2025-10-15, Similarity: 0.87)
Summary: Investigated socket timeout issues in the network layer, identified default timeout was too short, increased to 120 seconds.
Exchanges: 5

### Conversation: "Retry logic implementation" (ID: 156, Date: 2025-10-20, Similarity: 0.73)
Summary: Added exponential backoff for failed connections, implemented retry decorator pattern.
Exchanges: 8

#### Relevant Exchanges:

**Exchange ID: 456** (Conversation: 123, Similarity: 0.91)
- User: Getting socket timeouts after 30 seconds when connecting to the API...
- Assistant: Let me check the socket configuration. I'll look at the timeout settings in the network module...

**Exchange ID: 457** (Conversation: 123, Similarity: 0.88)
- User: How do I increase the timeout?
- Assistant: Set SO_RCVTIMEO to 120 seconds in the socket options. Here's the code change...
```

---

## LLM Tool: fetch_conversation_details

**Purpose:** Allow the LLM to drill into specific conversations/exchanges when RAG metadata indicates relevance.

**Two-tier RAG system:**
1. **Tier 1 (Automatic):** RAG injects high-level summaries with metadata
2. **Tier 2 (On-demand):** LLM calls tool to get full details

**Benefits:**
- **Token efficiency:** Don't bloat context with full transcripts upfront
- **LLM agency:** LLM decides what's worth investigating
- **Precision:** Can drill into specific exchanges
- **Cost control:** Only fetch details when needed

### Tool Specification

```ruby
class FetchConversationDetails
  PARAMETERS = {
    conversation_id: {
      type: "integer",
      description: "Conversation ID from RAG context metadata. Get full conversation details."
    },
    exchange_id: {
      type: "integer",
      description: "Specific exchange ID from RAG context. Get single exchange details."
    },
    include_full_transcript: {
      type: "boolean",
      default: false,
      description: "Include all messages (tool calls, intermediate steps), not just user/assistant pairs."
    }
  }.freeze

  def execute(context:, conversation_id: nil, exchange_id: nil, include_full_transcript: false)
    if exchange_id
      fetch_exchange_details(context, exchange_id, include_full_transcript)
    elsif conversation_id
      fetch_conversation_details(context, conversation_id, include_full_transcript)
    else
      { "error" => "Must provide either conversation_id or exchange_id" }
    end
  end

  private

  def fetch_conversation_details(context, conversation_id, include_full)
    history = context["history"]
    conversation = history.get_conversation(conversation_id)

    return { "error" => "Conversation not found" } unless conversation

    exchanges = history.exchanges(conversation_id: conversation_id)

    {
      "conversation_id" => conversation["id"],
      "title" => conversation["title"],
      "summary" => conversation["summary"],
      "created_at" => conversation["created_at"],
      "status" => conversation["status"],
      "exchanges" => exchanges.map do |exch|
        format_exchange(exch, include_full, history)
      end
    }
  end

  def fetch_exchange_details(context, exchange_id, include_full)
    history = context["history"]
    exchange = history.get_exchange(exchange_id)

    return { "error" => "Exchange not found" } unless exchange

    {
      "exchange_id" => exchange["id"],
      "conversation_id" => exchange["conversation_id"],
      "summary" => exchange["summary"],
      "user_message" => exchange["user_message"],
      "assistant_message" => exchange["assistant_message"],
      "started_at" => exchange["started_at"],
      "completed_at" => exchange["completed_at"],
      "messages" => include_full ? fetch_full_messages(history, exchange_id) : nil
    }
  end

  def format_exchange(exchange, include_full, history)
    result = {
      "exchange_id" => exchange["id"],
      "summary" => exchange["summary"],
      "user_message" => exchange["user_message"],
      "assistant_message" => exchange["assistant_message"],
      "completed_at" => exchange["completed_at"]
    }

    result["messages"] = fetch_full_messages(history, exchange["id"]) if include_full

    result
  end

  def fetch_full_messages(history, exchange_id)
    history.messages(exchange_id: exchange_id).map do |msg|
      {
        "role" => msg["role"],
        "content" => msg["content"],
        "tool_calls" => msg["tool_calls"],
        "tool_result" => msg["tool_result"]
      }
    end
  end
end
```

### Example Usage Flow

```markdown
# User asks: "How did we fix that socket timeout issue?"

# RAG injects:
## Related Past Conversations
### Conversation: "Debug connection timeouts" (ID: 123, Similarity: 0.87)
Summary: Investigated socket timeout issues...

# LLM thinks: "This looks relevant, let me get details"

# LLM calls tool:
fetch_conversation_details(conversation_id: 123)

# Tool returns:
{
  "conversation_id": 123,
  "title": "Debug connection timeouts",
  "summary": "...",
  "exchanges": [
    {
      "exchange_id": 456,
      "user_message": "Getting socket timeouts after 30 seconds...",
      "assistant_message": "Let me check the socket configuration...",
      "summary": "Identified default timeout was too short"
    },
    ...
  ]
}

# LLM responds with specific details from the fetched conversation
```

---

## Command Interface

### /summarizer Command

**Purpose:** Control conversation and exchange summarization workers.

**Syntax:**
```
/summarizer                     # Status of all summarizers
/summarizer conversation        # Status of conversation summarizer only
/summarizer exchange            # Status of exchange summarizer only
/summarizer on                  # Start both summarizers + embeddings
/summarizer off                 # Stop both summarizers
/summarizer conversation on     # Start conversation summarizer
/summarizer conversation off    # Stop conversation summarizer
/summarizer exchange on         # Start exchange summarizer
/summarizer exchange off        # Stop exchange summarizer
```

**Example outputs:**

```bash
> /summarizer
Conversation Summarizer: RUNNING
  Progress: 3/10 conversations
  Completed: 3, Failed: 0
  Current: conversation_id=125
  Spend: $0.15

Exchange Summarizer: RUNNING
  Progress: 15/50 exchanges
  Completed: 15, Failed: 0
  Current: exchange_id=892
  Spend: $0.42

Embedding Pipeline: RUNNING (see /embeddings for details)
```

```bash
> /summarizer conversation
Conversation Summarizer: IDLE
  Total processed this session: 47
  Completed: 47, Failed: 0
  Spend: $2.31

All conversations are summarized. Worker is idle.
```

**Implementation notes:**
- Stores worker state in ConfigStore (auto-restart across sessions)
- Status includes spend tracking (sum of LLM costs)
- Shows current item being processed
- Distinguishes RUNNING (actively processing) vs IDLE (waiting for work)

### /embeddings Command

**Purpose:** Control embedding pipeline and manage embeddings.

**Syntax:**
```
/embeddings                         # Status
/embeddings on                      # Start pipeline
/embeddings off                     # Stop pipeline
/embeddings rebuild                 # Re-embed all summaries (delete + recreate)
/embeddings rebuild conversations   # Re-embed just conversations
/embeddings rebuild exchanges       # Re-embed just exchanges
```

**Example outputs:**

```bash
> /embeddings
Embedding Pipeline: RUNNING
  State: Processing batch
  Progress: 127/150 embeddings
  Completed: 127, Failed: 0
  Current batch: 23 items
  Spend: $0.19

⚠️  Retry queue: 3 items (next retry in 4 seconds)
```

```bash
> /embeddings
Embedding Pipeline: IDLE
  Total embeddings: 1,247
    - Conversation summaries: 247
    - Exchange summaries: 1,000

⚠️  Warning: 27 summaries are awaiting embeddings (pipeline is OFF)
```

```bash
> /embeddings rebuild
⚠️  WARNING: This will delete and recreate ALL embeddings.
This operation will:
  - Delete 1,247 existing embeddings
  - Re-embed 247 conversation summaries
  - Re-embed 1,000 exchange summaries
  - Cost approximately $0.12 (OpenAI API)

Type 'yes' to confirm: yes

Embeddings cleared. Pipeline will recreate them.
Processing: 0/1,247 completed...
```

**Implementation notes:**
- Shows breakdown of embedding types
- Warns if summaries exist without embeddings
- Rebuild requires explicit "yes" confirmation
- Shows retry queue status (exponential backoff)

### /rag Command

**Purpose:** Configure RAG system and view status.

**Syntax:**
```
/rag                    # Show RAG status and config
/rag on                 # Enable RAG retrieval
/rag off                # Disable RAG retrieval
/rag config             # Show detailed configuration
/rag set <key> <value>  # Update configuration
```

**Example outputs:**

```bash
> /rag
RAG Status: ENABLED

Embeddings:
  - Conversation summaries: 247 embedded
  - Exchange summaries: 1,000 embedded
  - Total vectors: 1,247

Configuration:
  - Conversation retrieval limit: 3
  - Exchange limit per conversation: 2
  - Minimum similarity threshold: 0.70

Last retrieval: 2 seconds ago (3 conversations, 5 exchanges)
```

```bash
> /rag config
RAG Configuration:
  rag_enabled: true
  rag_conversation_limit: 3
  rag_exchange_limit_per_conversation: 2
  rag_min_similarity: 0.70

To update: /rag set <key> <value>
Example: /rag set rag_conversation_limit 5
```

```bash
> /rag set rag_conversation_limit 5
Updated: rag_conversation_limit = 5
RAG will now retrieve up to 5 related conversations per query.
```

**Implementation notes:**
- Shows embedding counts by type
- Displays current configuration values
- Allows runtime configuration changes (persisted to ConfigStore)
- Validates configuration values (limits must be > 0, similarity must be 0-1)

---

## Configuration

### ConfigStore Keys

All RAG-related configuration stored in `appconfig` table:

```ruby
{
  # RAG retrieval
  "rag_enabled" => true,                              # Master toggle for RAG
  "rag_conversation_limit" => 3,                      # Top N conversations to retrieve
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
  "embedding_max_retries" => 6,                       # Max retry attempts (exponential backoff)

  # Cost controls (future)
  "min_messages_for_exchange_summary" => 1,           # Skip exchanges with < N messages
  "min_exchanges_for_conversation_summary" => 1       # Skip conversations with < N exchanges
}
```

**Default values:** Set during schema initialization if not present.

**Persistence:** Changes via `/rag set` or `/summarizer` commands are saved to ConfigStore and persist across sessions.

### Daemon Lifecycle: Auto-Start

**Behavior:** Workers auto-start based on last saved state in ConfigStore.

**On application startup:**
```ruby
# In Application#initialize
def initialize
  # ... existing setup ...

  # Auto-start background workers based on saved state
  auto_start_background_workers()
end

def auto_start_background_workers
  config = @config_store.get_all()

  if config["summarizer_conversation_enabled"]
    @background_worker_manager.start_conversation_summarizer_worker()
  end

  if config["summarizer_exchange_enabled"]
    @background_worker_manager.start_exchange_summarizer_worker()
  end

  if config["embedding_pipeline_enabled"]
    @background_worker_manager.start_embedding_pipeline_worker()
  end
end
```

**When user toggles workers:**
```ruby
# /summarizer conversation on
@background_worker_manager.start_conversation_summarizer_worker()
@config_store.set("summarizer_conversation_enabled", true)  # Persist state

# /summarizer conversation off
@background_worker_manager.stop_conversation_summarizer_worker()
@config_store.set("summarizer_conversation_enabled", false) # Persist state
```

**Result:** Workers remember their state across sessions. If user enables summarization and quits, it will resume on next launch.

---

## Implementation Phases

### Phase 0: Man-Page Infrastructure Removal

**Estimated time:** 30 minutes

**Goals:**
- Remove all man-page indexing code
- Clean up database (delete man_page embeddings)
- Clean foundation for RAG implementation

**Tasks:**
1. Delete core classes:
   - `lib/nu/agent/man_page_indexer.rb`
   - `lib/nu/agent/man_indexer.rb`
   - `lib/nu/agent/tools/man_indexer.rb`
   - `lib/nu/agent/commands/index_man_command.rb`

2. Remove from integration points:
   - `BackgroundWorkerManager`: Remove `man_indexer_status`, `start_man_indexer_worker()`, `build_man_indexer_status()`
   - `Application`: Remove `man_indexer_status` attr_reader
   - `ToolRegistry`: Unregister `man_indexer` tool

3. Delete test files:
   - `spec/nu/agent/man_page_indexer_spec.rb`
   - `spec/nu/agent/commands/index_man_command_spec.rb`
   - Clean up references in `spec/nu/agent/background_worker_manager_spec.rb`

4. Clean database:
   ```sql
   DELETE FROM text_embedding_3_small WHERE kind = 'man_page';
   ```

5. Run test suite: `bundle exec rspec`

6. Update documentation:
   - Remove man-page references from README
   - Update help text

**Validation:**
- All tests pass
- No references to "man" or "ManPage" in codebase (except man command tool)
- No man_page embeddings in database

**Git commit:** "Remove man-page indexing infrastructure"

---

### Phase 1: Database Schema Changes

**Estimated time:** 45 minutes

**Goals:**
- Enable VSS extension
- Add foreign keys to embeddings table
- Create HNSW index
- Add similarity search methods

**Tasks:**

1. **Enable VSS extension** in `SchemaManager`:
   ```ruby
   def enable_vss_extension
     @connection.query("INSTALL vss")
     @connection.query("LOAD vss")
   end
   ```
   Call during `setup_database()`.

2. **Add foreign key columns:**
   ```ruby
   def migrate_embeddings_table
     @connection.query(<<~SQL)
       ALTER TABLE text_embedding_3_small
         ADD COLUMN conversation_id INTEGER REFERENCES conversations(id);

       ALTER TABLE text_embedding_3_small
         ADD COLUMN exchange_id INTEGER REFERENCES exchanges(id);
     SQL
   end
   ```

3. **Create indexes:**
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

4. **Add similarity search to `EmbeddingStore`:**
   - `search_similar_conversations(query_embedding:, limit:, min_similarity:, exclude_conversation_id:)`
   - `search_similar_exchanges(query_embedding:, conversation_ids:, limit_per_conversation:, min_similarity:)`
   - Helper: `format_embedding(array)` - Converts Ruby array to DuckDB array literal

5. **Write tests:**
   - Test VSS extension loads
   - Test similarity search returns results ordered by similarity
   - Test exclude_conversation_id works
   - Test limit_per_conversation works (window function)

**Validation:**
- Run test suite
- Manually test similarity search:
  ```ruby
  # In console
  embeddings_client = Clients::OpenAIEmbeddings.new
  query_embedding = embeddings_client.embed("test query")
  results = embedding_store.search_similar_conversations(
    query_embedding: query_embedding,
    limit: 5,
    min_similarity: 0.5
  )
  puts results.inspect
  ```

**Git commit:** "Add VSS extension and similarity search for RAG"

---

### Phase 2: ExchangeSummarizer Worker

**Estimated time:** 1.5 hours

**Goals:**
- Create ExchangeSummarizer class
- Integrate with BackgroundWorkerManager
- Add History facade methods
- Implement continuous daemon mode

**Tasks:**

1. **Create `lib/nu/agent/exchange_summarizer.rb`:**
   - Similar structure to ConversationSummarizer
   - Query: `SELECT * FROM exchanges WHERE summary IS NULL AND status = 'completed' AND conversation_id != ? ORDER BY completed_at DESC LIMIT 100`
   - Prompt: Focus on single exchange (user + assistant pair)
   - Signal embedding pipeline after each summary
   - Continuous daemon with condition variable

2. **Add to BackgroundWorkerManager:**
   ```ruby
   def initialize(...)
     @exchange_summarizer_status = build_exchange_summarizer_status
   end

   def start_exchange_summarizer_worker
     worker = ExchangeSummarizer.new(...)
     thread = worker.start_worker
     @active_threads << thread
   end

   def signal_exchange_summarizer
     @exchange_summarizer&.signal
   end
   ```

3. **Add History methods:**
   ```ruby
   def get_unsummarized_exchanges(exclude_conversation_id:)
     @exchange_repo.get_unsummarized_exchanges(exclude_conversation_id: exclude_conversation_id)
   end

   def update_exchange_summary(exchange_id:, summary:, model:, cost:)
     @exchange_repo.update_exchange_summary(...)
   end
   ```

4. **Add to Application:**
   ```ruby
   attr_reader :exchange_summarizer_status

   def start_exchange_summarizer_worker
     @background_worker_manager.start_exchange_summarizer_worker
   end
   ```

5. **Write tests:**
   - Test worker finds unsummarized exchanges
   - Test worker excludes current conversation
   - Test summary is stored in database
   - Test worker signals embedding pipeline
   - Test worker goes idle when no work
   - Test worker wakes on signal

**Validation:**
- Create exchanges manually, verify worker picks them up
- Check summaries are stored: `SELECT id, summary FROM exchanges WHERE summary IS NOT NULL`
- Verify worker status shows correct progress

**Git commit:** "Add ExchangeSummarizer background worker"

---

### Phase 3: EmbeddingPipeline Worker

**Estimated time:** 2 hours

**Goals:**
- Create EmbeddingPipeline class
- Implement batching and retry logic
- Store embeddings with foreign keys
- Integrate with BackgroundWorkerManager

**Tasks:**

1. **Create `lib/nu/agent/embedding_pipeline.rb`:**
   - Find conversations/exchanges with summaries but no embeddings (LEFT JOIN)
   - Batch up to 100 items per API call
   - Store embeddings atomically (transaction)
   - Exponential backoff retry queue (1s, 2s, 4s, 8s, 16s, 32s, give up)
   - Continuous daemon with signal + 5-second poll

2. **Add History methods:**
   ```ruby
   def find_conversations_needing_embeddings(limit:)
     # LEFT JOIN to find conversations with summary but no embedding
   end

   def find_exchanges_needing_embeddings(limit:)
     # LEFT JOIN to find exchanges with summary but no embedding
   end

   def store_conversation_embedding(conversation_id:, content:, embedding:)
     @embedding_store.store_embedding(
       kind: 'conversation_summary',
       conversation_id: conversation_id,
       content: content,
       embedding: embedding
     )
   end

   def store_exchange_embedding(exchange_id:, content:, embedding:)
     @embedding_store.store_embedding(
       kind: 'exchange_summary',
       exchange_id: exchange_id,
       content: content,
       embedding: embedding
     )
   end
   ```

3. **Update EmbeddingStore:**
   ```ruby
   def store_embedding(kind:, conversation_id: nil, exchange_id: nil, content:, embedding:)
     embedding_str = format_embedding(embedding)

     @connection.query(<<~SQL)
       INSERT INTO text_embedding_3_small
         (kind, conversation_id, exchange_id, content, embedding)
       VALUES
         ('#{escape_sql(kind)}', #{conversation_id || 'NULL'},
          #{exchange_id || 'NULL'}, '#{escape_sql(content)}', #{embedding_str})
     SQL
   end
   ```

4. **Add to BackgroundWorkerManager:**
   - `@embedding_pipeline_status`
   - `start_embedding_pipeline_worker()`
   - `signal_embedding_pipeline()`

5. **Wire up signals:**
   - In `ChatLoopOrchestrator#complete_exchange()`: Signal both summarizers and embedding pipeline
   - In `ConversationSummarizer`: Signal embedding pipeline after each summary
   - In `ExchangeSummarizer`: Signal embedding pipeline after each summary

6. **Write tests:**
   - Test finds summaries without embeddings
   - Test batching (multiple items in one API call)
   - Test atomic transaction (all or nothing)
   - Test retry queue with exponential backoff
   - Test signals wake worker immediately
   - Test fallback polling (every 5 seconds)

**Validation:**
- Create summaries manually, verify embeddings appear within 5 seconds
- Check embeddings have foreign keys: `SELECT conversation_id, exchange_id, kind FROM text_embedding_3_small`
- Test failure handling: Break OpenAI API key, verify retry queue works

**Git commit:** "Add EmbeddingPipeline background worker with retry logic"

---

### Phase 4: ConversationRetriever & RAG Integration

**Estimated time:** 2.5 hours (1.5 + 1)

**Goals:**
- Create ConversationRetriever class
- Integrate RAG into ChatLoopOrchestrator
- Update DocumentBuilder to format RAG context
- Add fetch_conversation_details tool

**Tasks:**

1. **Create `lib/nu/agent/conversation_retriever.rb`:**
   - Embed user query
   - Search conversation summaries (top N)
   - Search exchange summaries within those conversations (top M per conversation)
   - Enrich with metadata (title, dates, counts)
   - Return structured hash

2. **Update ChatLoopOrchestrator:**
   - Add `retrieve_rag_context_if_enabled(user_input)` method
   - Call before building context
   - Pass `rag_context` to DocumentBuilder
   - Graceful degradation on errors

3. **Update DocumentBuilder:**
   - Add `build_rag_section(rag_context)` method
   - Format conversations with metadata (ID, title, similarity, date)
   - Format exchanges with metadata (ID, conversation_id, similarity)
   - Truncate long messages to 200 chars
   - Mention fetch_conversation_details tool

4. **Create `lib/nu/agent/tools/fetch_conversation_details.rb`:**
   - Parameters: conversation_id, exchange_id, include_full_transcript
   - Fetch conversation or exchange from History
   - Return structured JSON with metadata
   - Include all exchanges if conversation_id provided
   - Include full message transcript if requested

5. **Register tool in ToolRegistry:**
   ```ruby
   register_tool(Tools::FetchConversationDetails.new)
   ```

6. **Write tests:**
   - Test ConversationRetriever returns relevant results
   - Test hierarchical search (conversations → exchanges)
   - Test exclude_conversation_id works
   - Test RAG section appears in context document
   - Test fetch_conversation_details tool returns correct data
   - Test graceful degradation when RAG fails

**Validation:**
- Create conversations with summaries and embeddings
- Ask query similar to past conversation
- Verify RAG context appears in DocumentBuilder output
- Verify LLM can call fetch_conversation_details tool
- Test with RAG disabled (`/rag off`)

**Git commits:**
- "Add ConversationRetriever for RAG semantic search"
- "Integrate RAG into ChatLoopOrchestrator and DocumentBuilder"
- "Add fetch_conversation_details tool for LLM-driven retrieval"

---

### Phase 5: Command Interface

**Estimated time:** 1.5 hours

**Goals:**
- Implement /summarizer command with subcommands
- Implement /embeddings command with rebuild
- Implement /rag command for configuration
- Add auto-start based on ConfigStore

**Tasks:**

1. **Create `lib/nu/agent/commands/summarizer_command.rb`:**
   - Parse subcommands (conversation, exchange, on, off)
   - Show status (all, conversation, exchange)
   - Start/stop workers
   - Update ConfigStore for auto-start

2. **Create `lib/nu/agent/commands/embeddings_command.rb`:**
   - Show status (progress, retry queue, warnings)
   - Start/stop pipeline
   - Rebuild command with confirmation prompt
   - Update ConfigStore for auto-start

3. **Create `lib/nu/agent/commands/rag_command.rb`:**
   - Show status (embedding counts, last retrieval)
   - Show configuration
   - Enable/disable RAG
   - Set configuration values (with validation)
   - Persist to ConfigStore

4. **Add auto-start to Application:**
   ```ruby
   def initialize
     # ... existing setup ...
     auto_start_background_workers()
   end

   def auto_start_background_workers
     config = @config_store.get_all()

     start_conversation_summarizer_worker if config["summarizer_conversation_enabled"]
     start_exchange_summarizer_worker if config["summarizer_exchange_enabled"]
     start_embedding_pipeline_worker if config["embedding_pipeline_enabled"]
   end
   ```

5. **Add configuration defaults in SchemaManager:**
   ```ruby
   def initialize_default_config
     defaults = {
       "rag_enabled" => true,
       "rag_conversation_limit" => 3,
       "rag_exchange_limit_per_conversation" => 2,
       "rag_min_similarity" => 0.7,
       "summarizer_conversation_enabled" => true,
       "summarizer_exchange_enabled" => true,
       "embedding_pipeline_enabled" => true,
       ...
     }

     defaults.each do |key, value|
       @config_store.set(key, value) unless @config_store.exists?(key)
     end
   end
   ```

6. **Write tests:**
   - Test command parsing (all subcommands)
   - Test status output formatting
   - Test on/off toggles update ConfigStore
   - Test rebuild confirmation prompt
   - Test configuration validation (limits > 0, similarity 0-1)
   - Test auto-start loads from ConfigStore

**Validation:**
- Test all command variations manually
- Verify workers auto-start on application launch
- Test rebuild deletes and recreates embeddings
- Test configuration changes persist across restarts

**Git commit:** "Add command interface for summarizers, embeddings, and RAG"

---

### Phase 6: Testing & Refinement

**Estimated time:** 1 hour

**Goals:**
- Integration testing
- Performance validation
- Cost estimation
- Documentation updates

**Tasks:**

1. **Integration tests:**
   - End-to-end flow: Create conversation → Summarize → Embed → Query with RAG
   - Test with multiple conversations
   - Test similarity threshold filtering
   - Test exclusion of current conversation
   - Test graceful degradation (RAG disabled, API failures)

2. **Performance testing:**
   - Measure RAG retrieval latency (should be < 500ms)
   - Measure embedding pipeline throughput
   - Test with 100, 1000, 10000 embeddings

3. **Cost analysis:**
   - Calculate summarization costs (average per conversation/exchange)
   - Calculate embedding costs (per summary)
   - Estimate storage requirements (embeddings table size)

4. **Documentation:**
   - Update README with RAG section
   - Add examples to help text
   - Document configuration options
   - Add architecture diagram to docs/

5. **Edge cases:**
   - Test with no embeddings (graceful fallback)
   - Test with corrupted embeddings
   - Test with very long summaries (truncation)
   - Test with identical conversations (similarity = 1.0)

**Validation:**
- All tests pass (unit + integration)
- RAG retrieval works in real usage
- Performance is acceptable (< 500ms retrieval)
- Documentation is clear and complete

**Git commit:** "Add integration tests and documentation for RAG system"

---

### Phase Summary & Timeline

| Phase | Tasks | Time | Priority | Commit |
|-------|-------|------|----------|--------|
| 0 | Remove man-pages | 30 min | High | After completion |
| 1 | Database schema | 45 min | High | After completion |
| 2 | ExchangeSummarizer | 1.5 hrs | High | After completion |
| 3 | EmbeddingPipeline | 2 hrs | High | After completion |
| 4 | ConversationRetriever + RAG Integration | 2.5 hrs | Medium | After completion (may be 2-3 commits) |
| 5 | Commands | 1.5 hrs | Low | After completion |
| 6 | Testing | 1 hr | Low | After completion |

**Total estimated time:** 9-10 hours of focused development

**Dependencies:**
- Phases 0-1 are sequential (foundation)
- Phases 2-3 can be done in parallel after Phase 1
- Phase 4 depends on Phases 1-3
- Phase 5 can be done anytime after Phase 2-3
- Phase 6 is final validation

**Recommended order:**
1. Phase 0 (clean foundation)
2. Phase 1 (enable infrastructure)
3. Phases 2 & 3 in parallel (workers)
4. Phase 4 (RAG integration)
5. Phase 5 (commands)
6. Phase 6 (testing)

---

## Testing Strategy

### Integration Tests (Automated)

**Test scope:** Core worker logic and RAG retrieval

**Test files to create:**
- `spec/nu/agent/exchange_summarizer_spec.rb`
- `spec/nu/agent/embedding_pipeline_spec.rb`
- `spec/nu/agent/conversation_retriever_spec.rb`
- `spec/nu/agent/tools/fetch_conversation_details_spec.rb`

**Key test scenarios:**

1. **ExchangeSummarizer:**
   - Finds unsummarized exchanges
   - Excludes current conversation
   - Stores summaries in database
   - Signals embedding pipeline
   - Goes idle when no work
   - Wakes on signal

2. **EmbeddingPipeline:**
   - Finds summaries without embeddings (LEFT JOIN)
   - Batches multiple summaries per API call
   - Stores embeddings atomically (transaction)
   - Handles API failures with exponential backoff
   - Retry queue works correctly
   - Signals wake worker immediately

3. **ConversationRetriever:**
   - Returns most similar conversations
   - Excludes current conversation
   - Limits results to configured count
   - Filters by similarity threshold
   - Hierarchical search works (conversations → exchanges)
   - Returns enriched metadata

4. **fetch_conversation_details tool:**
   - Returns conversation details by ID
   - Returns exchange details by ID
   - Includes full transcript when requested
   - Handles not found errors gracefully

**Mocking strategy:**
- Mock OpenAI API calls (embeddings_client)
- Use real DuckDB in-memory database for tests
- Mock Application#output_line (avoid test output)

### Manual Testing

**Test scope:** Command interface and user experience

**Workflows to test:**

1. **Initial setup:**
   ```bash
   > /summarizer on
   > /embeddings on
   > /rag on
   # Verify workers start
   # Create some conversations
   # Verify summarization happens
   # Verify embeddings appear
   ```

2. **RAG retrieval:**
   ```bash
   # Create conversation about "fixing timeout bug"
   # Wait for summarization + embedding
   # Start new conversation
   # Ask "how did we fix the timeout issue?"
   # Verify RAG context includes previous conversation
   # Verify LLM can use fetch_conversation_details tool
   ```

3. **Worker lifecycle:**
   ```bash
   > /summarizer off
   # Create exchanges, verify not summarized
   > /summarizer on
   # Verify worker catches up on backlog
   # Quit application, restart
   # Verify workers auto-start
   ```

4. **Rebuild:**
   ```bash
   > /embeddings rebuild
   # Confirm with "yes"
   # Verify embeddings deleted
   # Verify re-embedding happens
   # Verify RAG still works after rebuild
   ```

5. **Configuration:**
   ```bash
   > /rag config
   > /rag set rag_conversation_limit 5
   > /rag set rag_min_similarity 0.8
   # Ask query, verify new limits applied
   ```

6. **Failure handling:**
   ```bash
   # Break OpenAI API key
   > /embeddings
   # Verify retry queue shows failures
   # Fix API key
   # Verify retry queue processes
   ```

**Manual test checklist:**
- [ ] Workers auto-start on launch
- [ ] RAG context appears for similar queries
- [ ] LLM can fetch conversation details
- [ ] Commands parse all subcommands correctly
- [ ] Status output is clear and accurate
- [ ] Rebuild works and requires confirmation
- [ ] Configuration changes persist
- [ ] Graceful degradation (RAG off, API down)

---

## Success Criteria

**Phase 0 (Man-page removal):**
- [ ] All man-page code deleted
- [ ] All tests pass
- [ ] No man_page embeddings in database

**Phase 1 (Schema):**
- [ ] VSS extension loads without error
- [ ] HNSW index created
- [ ] Similarity search returns ordered results
- [ ] Foreign keys work (can query embeddings by conversation_id)

**Phase 2 (ExchangeSummarizer):**
- [ ] Worker finds and summarizes exchanges
- [ ] Summaries stored in exchanges.summary column
- [ ] Worker excludes current conversation
- [ ] Worker goes idle when no work
- [ ] Signals embedding pipeline

**Phase 3 (EmbeddingPipeline):**
- [ ] Worker finds summaries without embeddings
- [ ] Batches multiple embeddings per API call
- [ ] Stores embeddings with correct foreign keys
- [ ] Retry queue handles failures with exponential backoff
- [ ] Worker wakes immediately on signal
- [ ] Falls back to 5-second polling

**Phase 4 (RAG):**
- [ ] ConversationRetriever returns relevant results
- [ ] Hierarchical search works (conversations → exchanges)
- [ ] RAG context appears in DocumentBuilder output
- [ ] fetch_conversation_details tool works
- [ ] Graceful degradation (no crash if RAG fails)

**Phase 5 (Commands):**
- [ ] All command variations work (/summarizer, /embeddings, /rag)
- [ ] Workers auto-start based on ConfigStore
- [ ] Status output is accurate
- [ ] Configuration changes persist
- [ ] Rebuild requires confirmation

**Phase 6 (Testing):**
- [ ] All integration tests pass
- [ ] Manual testing checklist complete
- [ ] RAG retrieval latency < 500ms
- [ ] Documentation updated

**Overall success:**
- [ ] Agent can reference past conversations in responses
- [ ] Users report improved context continuity
- [ ] System is stable (no crashes, no data loss)
- [ ] Performance is acceptable (retrieval < 500ms)
- [ ] Costs are reasonable (< $0.01 per query for embeddings)

---

## Performance & Cost Estimates

### Summarization Costs

**Model:** Haiku (cheapest for summaries, ~$0.25 per million input tokens)

**Conversation summary:**
- Input: ~500-2000 tokens (full conversation)
- Output: ~50-100 tokens (2-3 sentences)
- Cost: ~$0.001-0.005 per conversation

**Exchange summary:**
- Input: ~200-500 tokens (single exchange)
- Output: ~30-50 tokens (1-2 sentences)
- Cost: ~$0.0005-0.002 per exchange

**Example: 100 conversations with 5 exchanges each:**
- Conversation summaries: 100 × $0.003 = $0.30
- Exchange summaries: 500 × $0.001 = $0.50
- **Total summarization: ~$0.80**

### Embedding Costs

**Model:** text-embedding-3-small (~$0.02 per million tokens)

**Cost per embedding:**
- Input: ~50-100 tokens (summary text)
- Cost: ~$0.000002-0.000004 per embedding

**Example: 100 conversations + 500 exchanges:**
- 600 embeddings × $0.000003 = **$0.0018**

**Negligible!** Embedding costs are effectively free compared to summarization.

### RAG Retrieval Costs

**Per query:**
- Embed user query: ~$0.000002 (5-20 tokens)
- Vector search: Free (local DuckDB)
- **Total per query: ~$0.000002**

**Example: 1000 queries:**
- **$0.002** for embedding all queries

### Storage Requirements

**Per embedding:**
- 1536 floats × 4 bytes = 6,144 bytes = ~6 KB
- Plus metadata (IDs, content, timestamps): ~2 KB
- **Total: ~8 KB per embedding**

**Example: 10,000 embeddings:**
- 10,000 × 8 KB = **80 MB** in DuckDB

**Conclusion:** Storage is not a concern. Even 100,000 embeddings = 800 MB.

### Latency Estimates

**Summarization:**
- LLM call: ~1-3 seconds per summary (depends on model)
- Not blocking (background worker)

**Embedding:**
- OpenAI API: ~200-500ms for batch of 100
- Not blocking (background worker)

**RAG Retrieval:**
- Embed query: ~200ms (OpenAI API)
- Vector search: ~10-50ms (HNSW index, local)
- Enrich metadata: ~10ms (database queries)
- **Total: ~250-300ms per query**

**Target: < 500ms** - Should be achievable even with 10,000+ embeddings.

### Scalability

**10,000 embeddings:**
- Storage: ~80 MB
- Retrieval: ~300ms
- Cost: ~$10-50 to generate (one-time)

**100,000 embeddings:**
- Storage: ~800 MB
- Retrieval: ~500-1000ms (HNSW approximation)
- Cost: ~$100-500 to generate (one-time)

**Recommendation:** Current design scales well to 10,000 conversations. Beyond that, may need to tune HNSW parameters or consider chunking strategies.

---

## Future Enhancements

### 1. Multi-Model Embeddings

**Idea:** Support multiple embedding models (OpenAI, Cohere, local models)

**Benefits:**
- Compare quality across models
- Cost optimization (cheaper models for less critical data)
- Privacy (local models for sensitive data)

**Implementation:**
- Add `embedding_model` column to track which model created each embedding
- Support different dimensionalities (768, 1536, 3072)
- Add model selection to configuration

### 2. Relevance Feedback

**Idea:** Let users upvote/downvote retrieved context

**Benefits:**
- Learn which retrievals are helpful
- Boost/penalize specific conversations in future retrievals
- Improve retrieval quality over time

**Implementation:**
- Add `relevance_score` column to track user feedback
- Multiply similarity score by relevance_score during retrieval
- Add commands: `/rag upvote <conversation_id>`, `/rag downvote <conversation_id>`

### 3. User-Provided Documents

**Idea:** Allow users to index their own documents (code files, notes, PDFs)

**Benefits:**
- Agent has access to project-specific knowledge
- Can reference documentation, specs, code
- More useful than just conversation history

**Implementation:**
- Add `kind='user_document'` embeddings
- Create `/index document <path>` command
- Chunking strategy (256-512 tokens per chunk)
- Include in RAG retrieval alongside conversations

### 4. Conversation Tagging

**Idea:** Manually or automatically tag conversations with topics/categories

**Benefits:**
- Filter retrieval by tag ("only search debugging conversations")
- Better organization of conversation history
- Improves precision for specific queries

**Implementation:**
- Add `tags` column to conversations table (JSON array)
- Auto-tagging via LLM during summarization
- Manual tagging: `/tag add debugging`, `/tag list`
- RAG filter: Only search conversations with specific tags

### 5. Temporal Weighting

**Idea:** Prefer more recent conversations in retrieval

**Benefits:**
- Recent solutions are more relevant (code changes over time)
- Avoids outdated information
- Balances similarity with recency

**Implementation:**
- Add time decay factor to similarity score
- Formula: `final_score = similarity * (1 - decay_factor * age_in_days)`
- Configurable decay rate (e.g., 0.01 per day = 10% penalty after 10 days)

### 6. Conversation Clustering

**Idea:** Group similar conversations into clusters/topics

**Benefits:**
- Visualize conversation themes over time
- "Show all debugging conversations"
- Better understanding of usage patterns

**Implementation:**
- Periodic clustering (k-means on embeddings)
- Store cluster_id in conversations table
- Add `/conversations clusters` command to explore

### 7. Cross-Conversation Context

**Idea:** Show how current conversation relates to past ones

**Benefits:**
- "This is your 5th conversation about authentication"
- Helps user realize patterns in their work
- Suggests related past work

**Implementation:**
- Track conversation → conversation relationships
- Display in session summary or dashboard
- Add to RAG context: "Related past work: ..."

### 8. Semantic Search Command

**Idea:** Direct semantic search without asking a question

**Benefits:**
- Power users can search conversation history directly
- Faster than asking a question
- Explore past work

**Implementation:**
- Add `/search <query>` command
- Returns list of similar conversations/exchanges
- Can pipe to other commands: `/search timeout | /open`

### 9. Export & Backup

**Idea:** Export conversations with embeddings for backup/portability

**Benefits:**
- Data portability
- Backup conversation history
- Share knowledge with team

**Implementation:**
- `/export conversations` - Export as JSON with embeddings
- `/import conversations <file>` - Import from backup
- Include summaries and embeddings in export

### 10. Multi-Agent Context Sharing

**Idea:** Multiple agent instances share conversation history

**Benefits:**
- Team collaboration (shared knowledge base)
- Cross-device sync
- Collective learning

**Implementation:**
- Sync DuckDB to cloud storage (S3, Dropbox)
- Merge embeddings from multiple instances
- Conflict resolution for concurrent edits

---

## Open Questions for Future Discussion

### Implementation Details

1. **Embedding query scope:**
   - **Question:** Should we embed just the user's latest message, or user + recent context (last 3 exchanges)?
   - **Options:**
     - A) Just user message - Fast, simple, focused
     - B) User + last 3 exchanges - More context, better matches
     - C) Entire conversation - Most context, might be too broad
   - **Current recommendation:** A (just user message)

2. **Batch commit strategy:**
   - **Question:** Should embeddings be committed as entire batch (atomic) or one-by-one (partial success)?
   - **Options:**
     - A) Entire batch atomic - If one fails, all fail together
     - B) One-by-one - Partial success possible, more transactions
   - **Current recommendation:** A (entire batch atomic)

3. **Context verbosity:**
   - **Question:** Should RAG context show full exchange content or truncate?
   - **Options:**
     - A) Truncate to 200 chars - Saves tokens, cleaner
     - B) Full content - More context for LLM
     - C) Configurable - User decides
   - **Current recommendation:** A (truncate to 200 chars)

4. **Worker idle timeout:**
   - **Question:** How long should workers sleep when idle?
   - **Options:**
     - A) 5 seconds - Fast response, more CPU
     - B) 30 seconds - Slower response, less CPU
     - C) Configurable - User decides
   - **Current recommendation:** B (30 seconds for summarizers, 5 seconds for embedding pipeline)

### Configuration & UX

5. **Cost filters:**
   - **Question:** Should we skip trivial exchanges/conversations to save money?
   - **Options:**
     - A) Summarize everything (when enabled)
     - B) Skip exchanges with < 3 messages (too trivial)
     - C) Configurable thresholds (min messages, min exchanges)
   - **Current recommendation:** A (summarize everything), add filtering later if needed

6. **Daemon lifecycle edge cases:**
   - **Question:** What if application crashes while workers are processing?
   - **Options:**
     - A) Resume on restart (check for incomplete work)
     - B) Start fresh (no recovery)
     - C) Store worker state in database (resume exactly where left off)
   - **Current recommendation:** B (start fresh), workers will catch up on next cycle

7. **Schema migration strategy:**
   - **Question:** How to handle existing embeddings without foreign keys?
   - **Options:**
     - A) Parse `source` string ("conversation_123" → 123) and backfill
     - B) Delete all embeddings and rebuild from summaries (clean slate)
     - C) Leave old records, only new embeddings use foreign keys
   - **Current recommendation:** B (clean slate - deleting man-pages anyway)

### Testing & Validation

8. **Manual vs automated testing:**
   - **Question:** How much should be automated vs manual testing?
   - **Options:**
     - A) Mostly automated (slower to write, faster to run)
     - B) Mostly manual (faster to write, slower to validate)
     - C) Hybrid (core logic automated, commands manual)
   - **Current recommendation:** C (hybrid approach)

9. **Performance targets:**
   - **Question:** What's acceptable RAG retrieval latency?
   - **Options:**
     - A) < 200ms - Very fast, strict
     - B) < 500ms - Reasonable, achievable
     - C) < 1000ms - Slower, more forgiving
   - **Current recommendation:** B (< 500ms)

### Architecture & Design

10. **Embedding storage alternatives:**
    - **Question:** Should we stick with DuckDB or consider external vector DB?
    - **Options:**
      - A) DuckDB with VSS extension - Simple, integrated, good for < 100k embeddings
      - B) External vector DB (Chroma, Weaviate) - More features, better at scale
      - C) Hybrid - DuckDB for metadata, external for vectors
    - **Current recommendation:** A (DuckDB), revisit if performance issues arise

11. **Summary timing:**
    - **Question:** When should exchanges be summarized?
    - **Options:**
      - A) Immediately after completion - Real-time, always current
      - B) After conversation ends - Batch efficiency, less cost
      - C) Configurable delay (5 min idle) - Balances real-time vs efficiency
    - **Current recommendation:** A (immediately after completion)

12. **Retrieval trigger:**
    - **Question:** Should RAG retrieval happen for every query, or only certain types?
    - **Options:**
      - A) Every query - Comprehensive, might be noisy
      - B) Only questions ("how", "what", "why") - Selective, might miss cases
      - C) LLM decides via tool call - Most flexible, adds latency
    - **Current recommendation:** A (every query), filter by similarity threshold

### Document Structure

13. **Code detail level:**
    - **Question:** How much real Ruby code vs pseudo-code?
    - **Options:**
      - A) Pseudo-code only - Conceptual, language-agnostic
      - B) Real Ruby code - Concrete, copy-paste ready
      - C) Mix - Ruby for critical sections, pseudo-code for flows
    - **Current recommendation:** C (mix of both)

14. **Diagram style:**
    - **Question:** ASCII art, Mermaid, or both?
    - **Options:**
      - A) ASCII art - Works everywhere, simple
      - B) Mermaid - Prettier, needs rendering
      - C) Both - Best of both worlds, more maintenance
    - **Current recommendation:** A (ASCII art for simplicity)

15. **Decision rationale:**
    - **Question:** Should we document why decisions were made?
    - **Options:**
      - A) Include rationale inline - Shows reasoning, longer doc
      - B) Just final design - Cleaner, less context
      - C) Separate decisions doc - Reference from main doc
    - **Current recommendation:** A (include brief rationale inline)

---

## References

- **DuckDB VSS Extension:** https://duckdb.org/docs/stable/core_extensions/vss
- **OpenAI Embeddings API:** https://platform.openai.com/docs/guides/embeddings
- **HNSW Algorithm:** Hierarchical Navigable Small Worlds for approximate nearest neighbor search
- **Related Documents:**
  - `docs/rag.md` - Generic RAG JSON payload examples (from other AI conversation)
  - `docs/architecture-analysis.md` - Current nu-agent architecture
  - `docs/design.md` - Database schema design

---

## Glossary

- **RAG:** Retrieval-Augmented Generation - Injecting retrieved documents into LLM context
- **VSS:** Vector Similarity Search - DuckDB extension for semantic search
- **HNSW:** Hierarchical Navigable Small Worlds - Approximate nearest neighbor algorithm
- **Embedding:** High-dimensional vector representation of text (1536 dimensions)
- **Cosine Similarity:** Measure of similarity between two vectors (0-1 scale)
- **Daemon:** Background process that runs continuously
- **Condition Variable:** Threading primitive for signaling between threads
- **Exponential Backoff:** Retry strategy with increasing delays (1s, 2s, 4s, 8s...)
- **Graceful Degradation:** System continues working even if some components fail
- **Hierarchical Search:** Multi-level search (conversations → exchanges)
- **Foreign Key:** Database constraint linking rows across tables
- **Transaction:** Atomic database operation (all or nothing)
- **Critical Section:** Code that must not run concurrently (protected by mutex)

---

**End of Implementation Plan**

*This document will continue to be refined as we work through implementation and discover edge cases, performance characteristics, and user needs.*
