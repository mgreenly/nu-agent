# Nu-Agent Architecture Design

## Database Schema

### Conceptual Hierarchy

```
Conversation (1)
  └── Exchange (1...N)
      └── Message (1...N)
```

### Tables

**conversations**
- Root container for a chat session
- Created on `/reset` or new session start
- Stores session-level metadata: title, summary, overall status

**exchanges**
- Single request-response cycle within a conversation
- Links to parent conversation via `conversation_id`
- Tracks: user request, assistant response, token counts, spend, timing
- Represents one complete interaction turn

**messages**
- Individual message unit (user, assistant, tool, or tool_result)
- Links to both `conversation_id` (for session queries) and `exchange_id` (for turn queries)
- Contains: role, content, tokens, tool_calls/results, errors
- Multiple messages form one exchange (e.g., user message → tool calls → tool results → assistant response)

### Foreign Keys

Enforced at **database level** with DuckDB foreign key constraints:
- `exchanges.conversation_id` → `conversations.id` (NOT NULL)
- `messages.conversation_id` → `conversations.id`
- `messages.exchange_id` → `exchanges.id`

Messages have dual foreign keys for efficient querying at both conversation and exchange levels. The database prevents orphaned records by rejecting inserts/updates that violate referential integrity.
