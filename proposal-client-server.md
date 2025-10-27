# Proposal: Client-Server Architecture

## Problem

The current monolithic architecture means:
- Memory and background services only exist when a client is running
- Each terminal session is isolated - no shared context across devices
- API credentials must be managed separately on each device
- No path to non-terminal interfaces (phone, web)

## Vision

Transform nu-agent into a **personal agent with persistent memory** that can be accessed from anywhere while maintaining the ability to work locally in code repositories.

## Architecture

**Server (Always Running)**
- Persistent memory storage (conversations, user data, learned context)
- Centralized credential management
- Background processing (summarization, indexing, pattern analysis)
- Content repository (books, documents, personal files)

**Clients (Run Anywhere)**
- LLM orchestration and tool execution
- Local filesystem access (for code agent use case)
- Fetches credentials and context from server
- Writes conversations back to server

**Key Insight:** This is a hybrid model. LLM calls and tool execution happen client-side (because tools need local filesystem access). Memory and credentials live server-side (for sharing across devices).

## Benefits

- Work seamlessly across devices with shared context
- Background intelligence processing (summarization, indexing)
- Access from terminal, phone, web, or future interfaces
- Centralized credential management (rotate once, works everywhere)
- Terminal code agent workflow remains unchanged

## Open Questions

1. Should clients be able to "continue" each other's conversations, or keep them isolated?
2. Single-user (one person, many devices) or multi-user (family, team)?
3. Server deployment: localhost only, or support remote deployment?
4. Migration path for existing users?
