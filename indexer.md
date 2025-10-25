# Man Page Embedding Indexer

## Overview

A background thread that indexes man pages into a vector database for semantic search. Uses OpenAI's text-embedding-3-small model to create embeddings from man page DESCRIPTION sections, stored in DuckDB with VSS (Vector Similarity Search) extension.

## Goals

- Enable semantic search across man pages ("how do I search files?" → grep, find, rg)
- Generic embeddings table supporting future document types (READMEs, code docs, etc.)
- Conservative rate limiting to avoid API throttling
- Incremental indexing (only process new/missing man pages)
- Track progress, costs, and provide status reporting

## Architecture

### Components

1. **OpenAI Client Extension** (`lib/nu/agent/clients/openai.rb`)
   - Add `generate_embedding(text)` method
   - Add rate limiting configuration for embeddings

2. **Database Schema** (`lib/nu/agent/history.rb`)
   - `text_embedding_3_small` table
   - Schema migrations in `setup_schema`

3. **Background Indexer Thread** (`lib/nu/agent/application.rb`)
   - `start_man_indexer_worker` method
   - `index_man_pages` worker loop

4. **Indexer Tool** (`lib/nu/agent/tools/man_indexer.rb`)
   - Reports status, progress, costs

5. **Commands**
   - `/index-man [on|off]` - Enable/disable indexing
   - Tool: `man_indexer` - Get status

## Database Schema

```sql
-- Generic embeddings table (model name in table name for future flexibility)
CREATE TABLE IF NOT EXISTS text_embedding_3_small (
  id INTEGER PRIMARY KEY DEFAULT nextval('text_embedding_3_small_id_seq'),
  kind TEXT NOT NULL,            -- 'man_page', 'readme', 'conversation', etc.
  source TEXT NOT NULL,          -- 'grep.1', 'ls.1', etc. (name.section format)
  content TEXT NOT NULL,         -- DESCRIPTION section text that was embedded
  embedding FLOAT[1536],         -- vector from OpenAI text-embedding-3-small
  indexed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  UNIQUE(kind, source)           -- prevent duplicate indexing
);

CREATE SEQUENCE IF NOT EXISTS text_embedding_3_small_id_seq START 1;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_kind ON text_embedding_3_small(kind);
CREATE INDEX IF NOT EXISTS idx_embedding_hnsw ON text_embedding_3_small USING HNSW(embedding);

-- VSS extension
INSTALL vss;
LOAD vss;
```

### Config Storage

Use existing `appconfig` table:
```sql
INSERT INTO appconfig (key, value) VALUES ('index_man_enabled', 'false');
```

Default: **off** (reset to off on every app startup)

## Rate Limiting

### OpenAI API Limits (Tier 1)
- 500 requests/minute
- 200K tokens/minute

### Conservative Indexer Settings
- **10 requests/minute** (well under limit)
- **10 man pages per request** (batch processing)
- **100 man pages/minute throughput**
- **~70 minutes** to index all ~7000 man pages

### Implementation
```ruby
# In OpenAI client
EMBEDDING_RATE_LIMIT = {
  requests_per_minute: 10,
  batch_size: 10
}
```

Worker sleeps between batches to maintain rate limit.

## Processing Flow

### 1. Startup
- App starts, sets `index_man_enabled = 'false'` in appconfig
- No indexing happens automatically

### 2. User Enables via `/index-man on`
- Sets `index_man_enabled = 'true'`
- Starts background indexer thread

### 3. Indexer Thread Loop

```ruby
def index_man_pages
  loop do
    break if @shutdown
    break unless index_man_enabled?

    # Get all man pages from system
    all_man_pages = get_all_man_pages  # via man -k .

    # Get already indexed man pages from DB
    indexed = get_indexed_sources(kind: 'man_page')

    # Calculate exclusive set (not yet indexed)
    to_index = all_man_pages - indexed

    break if to_index.empty?  # Done!

    # Process in batches of 10
    batch = to_index.take(10)

    # Extract DESCRIPTION sections
    contents = batch.map { |mp| extract_description(mp) }

    # Call OpenAI embeddings API (batch request)
    embeddings = openai.generate_embeddings(contents)

    # Store in database
    store_embeddings(batch, contents, embeddings)

    # Update status (progress, costs, etc.)
    update_status

    # Rate limiting: sleep to maintain 10 req/min
    sleep(6)  # 60 seconds / 10 requests
  end
end
```

### 4. Man Page Discovery

```bash
man -k . 2>/dev/null
```

Output format:
```
grep (1)             - print lines matching a pattern
ls (1)               - list directory contents
passwd (5)           - password file
```

Parse to extract:
- name: `grep`
- section: `1`
- source: `grep.1`
- description: `print lines matching a pattern`

### 5. Content Extraction

For each man page:

```bash
man -P cat <name> 2>/dev/null
```

Parse to extract DESCRIPTION section:
1. Find "DESCRIPTION" header line
2. Capture all text until next section header (OPTIONS, EXAMPLES, etc.)
3. Clean whitespace

### 6. Embedding Generation

Batch request to OpenAI:

```ruby
response = @client.embeddings(
  parameters: {
    model: 'text-embedding-3-small',
    input: [text1, text2, ..., text10]  # batch of 10
  }
)

embeddings = response['data'].map { |d| d['embedding'] }
```

### 7. Storage

```ruby
batch.each_with_index do |man_page, i|
  connection.query(<<~SQL)
    INSERT INTO text_embedding_3_small (kind, source, content, embedding)
    VALUES ('man_page', '#{man_page.source}', '#{contents[i]}', #{embeddings[i]})
    ON CONFLICT (kind, source) DO NOTHING
  SQL
end
```

## Status Tracking

Track in-memory (similar to summarizer):

```ruby
@man_indexer_status = {
  'running' => false,
  'total' => 0,
  'completed' => 0,
  'failed' => 0,
  'skipped' => 0,
  'current_batch' => nil,
  'session_spend' => 0.0,
  'session_tokens' => 0
}
```

Protected by `@status_mutex`.

## Error Handling

### Man Page Extraction Failures
- If `man <name>` fails → skip, increment `failed` counter, continue
- If DESCRIPTION not found → skip, increment `skipped` counter, continue
- If content is empty → skip

### API Failures
- Transient errors (rate limit, network) → retry with exponential backoff
- Permanent errors (invalid request) → skip batch, log, continue

### Token Limit Exceeded
- DESCRIPTION > 8191 tokens → truncate to 8000 tokens, log warning

## Commands

### `/index-man [on|off]`

**On:**
- Sets `appconfig.index_man_enabled = 'true'`
- Starts background indexer thread
- Shows status

**Off:**
- Sets `appconfig.index_man_enabled = 'false'`
- Thread checks flag and exits gracefully
- Shows final status

### Tool: `man_indexer`

Returns status information:
```json
{
  "enabled": true,
  "running": true,
  "progress": {
    "total": 7015,
    "completed": 1234,
    "failed": 5,
    "skipped": 12,
    "remaining": 5764
  },
  "session": {
    "spend": 0.0234,
    "tokens": 12450
  },
  "current_batch": ["grep.1", "ls.1", "find.1", ...]
}
```

## Querying Embeddings

Not part of this implementation, but the search API will be:

```ruby
def search_embeddings(query_text, kind: nil, limit: 10, threshold: 0.7)
  query_embedding = openai.generate_embedding(query_text)

  sql = <<~SQL
    SELECT kind, source, content,
           array_cosine_similarity(embedding, ?) as similarity
    FROM text_embedding_3_small
    WHERE array_cosine_similarity(embedding, ?) > ?
    #{kind ? "AND kind = ?" : ""}
    ORDER BY similarity DESC
    LIMIT ?
  SQL

  # query_embedding never stored, just used as parameter
  connection.query(sql, ...).to_a
end
```

## Cost Estimation

### OpenAI text-embedding-3-small Pricing
- $0.020 per 1M tokens

### Man Page Corpus
- ~7000 man pages
- DESCRIPTION sections average ~200 tokens (estimate)
- Total: ~1.4M tokens
- **Cost: ~$0.03** (3 cents!)

### Per Query
- Single query: ~50 tokens
- **Cost: ~$0.000001** (essentially free)

## Open Questions

### 1. DESCRIPTION Section Extraction
- **What if a man page has no DESCRIPTION section?**
  - Option A: Fall back to full text (truncated to 8K tokens)
  - Option B: Skip it
  - Option C: Use the short description from `man -k .`

- **What if DESCRIPTION is still >8191 tokens?**
  - Option A: Truncate to 8000 tokens
  - Option B: Skip it

### 2. Man Page Sections to Index
- **Index all sections (1-9)?**
- **Or just common ones: 1 (commands), 5 (formats), 7 (misc), 8 (admin)?**

### 3. Content Retrieval After Search
- When showing search results, do we:
  - **Option A**: Show the stored DESCRIPTION text from `content` field
  - **Option B**: Re-run `man <name>` to get fresh full content

### 4. Name/Section Parsing
- Use format `"grep.1"` for source field?
- Allows later retrieval via `man grep` or `man 1 grep`

## Implementation Order

1. ✅ Design schema
2. Add `generate_embedding` to OpenAI client
3. Add schema to `History#setup_schema`
4. Add `get_all_man_pages` method
5. Add `extract_description` method
6. Add background worker in Application
7. Add `/index-man` command
8. Add `man_indexer` tool
9. Test with small subset
10. Run full index

## Future Enhancements

- Index other document types (READMEs, code docs)
- Cross-source semantic search
- Incremental updates (detect new/changed man pages)
- Different embedding models (create new table per model)
- Smart chunking for large documents
- Query expansion and reranking
