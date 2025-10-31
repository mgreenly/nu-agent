# Nu::Agent Architecture Design Diagrams

This document provides a multi-level architectural view of the Nu::Agent codebase, starting with a high-level overview and progressively zooming into subsystems.

**Statistics:**
- ~11,409 lines of code
- 98.91% test coverage
- 1839+ tests
- 23 built-in tools
- 4 LLM providers
- 10+ models supported

---

## Table of Contents

1. [Level 1: High-Level Architecture](#level-1-high-level-architecture)
   - [System Overview](#system-overview)
   - [Data Flow Overview](#data-flow-overview)

2. [Level 2: Component Architecture](#level-2-component-architecture)
   - [Major Subsystems](#major-subsystems)

3. [Level 3: Subsystem Deep Dives](#level-3-subsystem-deep-dives)
   - [3.1 CLI Layer Architecture](#31-cli-layer-architecture)
   - [3.2 Agent Core - Orchestration](#32-agent-core---orchestration)
   - [3.3 Tool System Architecture](#33-tool-system-architecture)
   - [3.4 Memory & RAG System](#34-memory--rag-system)
   - [3.5 Multi-LLM Client Layer](#35-multi-llm-client-layer)
   - [3.6 Database Layer Architecture](#36-database-layer-architecture)
   - [3.7 Background Worker System](#37-background-worker-system)

4. [Level 4: Key Interaction Flows](#level-4-key-interaction-flows)
   - [4.1 Complete User Query Flow](#41-complete-user-query-flow)
   - [4.2 Background Worker Coordination](#42-background-worker-coordination)
   - [4.3 RAG Pipeline Data Flow](#43-rag-pipeline-data-flow)

5. [Summary](#summary)

---

## Level 1: High-Level Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐     │
│  │ ConsoleIO   │  │ Slash        │  │ Formatter           │     │
│  │ (Terminal)  │◄─┤ Commands     │  │ (Output Display)    │     │
│  └─────────────┘  └──────────────┘  └─────────────────────┘     │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                      APPLICATION LAYER                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Application (REPL Coordinator)              │   │
│  │  • Lifecycle management • Command routing • Cleanup      │   │
│  └─────────────────────────┬────────────────────────────────┘   │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                       ORCHESTRATION LAYER                       │
│  ┌─────────────────────┐        ┌──────────────────────────┐    │
│  │ ChatLoopOrch        │◄──────►│ ToolCallOrch             │    │
│  │ • Exchange mgmt     │        │ • Tool execution loop    │    │
│  │ • Context building  │        │ • Metrics tracking       │    │
│  │ • Transaction ctrl  │        │ • Error handling         │    │
│  └──────────┬──────────┘        └─────────┬────────────────┘    │
└─────────────┼─────────────────────────────┼─────────────────────┘
              │                             │
      ┌───────┴───────┐              ┌──────┴──────┐
      ▼               ▼              ▼             ▼
┌───────────┐   ┌─────────┐   ┌──────────┐  ┌─────────────┐
│           │   │         │   │          │  │             │
│  Memory   │   │  LLM    │   │  Tool    │  │  Database   │
│  & RAG    │   │ Clients │   │ Registry │  │  (DuckDB)   │
│           │   │         │   │          │  │             │
└─────┬─────┘   └────┬────┘   └─────┬────┘  └───────┬─────┘
      │              │              │               │
      └──────────────┴──────────────┴───────────────┘
                     │
          ┌──────────▼──────────┐
          │  Background Workers │
          │  • Summarization    │
          │  • Embeddings       │
          └─────────────────────┘
```

### Data Flow Overview

```
┌────────┐
│ User   │
│ Input  │
└───┬────┘
    │
    ▼
┌───────────────┐
│ InputProc     │─────→ Is command? ──Yes──→ CommandRegistry
└───┬───────────┘                                    │
    │                                                ▼
No (prompt)                                  Execute /command
    │
    ▼
┌───────────────────────────────────────────────────────────┐
│ ORCHESTRATION CYCLE (in thread, workers paused)           │
│                                                           │
│  1. Create Exchange (transaction)                         │
│     │                                                     │
│  2. Build Context Document                                │
│     ├─ Load History                                       │
│     ├─ RAG Retrieval (vector search)                      │
│     ├─ Tool Definitions                                   │
│     └─ User Query                                         │
│     │                                                     │
│  3. Tool Call Loop                                        │
│     ├─ LLM Request                                        │
│     ├─ Tool Execution (if requested)                      │
│     ├─ Save Messages (redacted)                           │
│     └─ Repeat until final answer                          │
│     │                                                     │
│  4. Commit Transaction                                    │
│                                                           │
└───────────────────┬───────────────────────────────────────┘
                    │
                    ▼
           ┌────────────────┐
           │ Display Result │
           └────────┬───────┘
                    │
                    ▼
           ┌────────────────┐
           │ Resume Workers │──→ Background summarization
           └────────────────┘    & embedding generation
```
---

## Level 2: Component Architecture

### Major Subsystems

```
╔════════════════════════════════════════════════════════════════╗
║                          CLI LAYER                             ║
╠════════════════════════════════════════════════════════════════╣
║  ┌──────────────┐  ┌──────────────┐  ┌─────────────────────┐   ║
║  │ ConsoleIO    │  │ Commands/    │  │ Formatter           │   ║
║  │              │  │              │  │                     │   ║
║  │ • Raw mode   │  │ • 15+ cmds   │  │ • Message fmt       │   ║
║  │ • Spinner    │  │ • Registry   │  │ • Token stats       │   ║
║  │ • History    │  │ • BaseCmd    │  │ • Debug levels      │   ║
║  └──────────────┘  └──────────────┘  └─────────────────────┘   ║
╚════════════════════════════════════════════════════════════════╝
                             │
╔════════════════════════════▼════════════════════════════════════╗
║                      AGENT CORE                                 ║
╠═════════════════════════════════════════════════════════════════╣
║  ┌────────────────────────────────────────────────────────────┐ ║
║  │             ChatLoopOrchestrator                           │ ║
║  │  • Exchange lifecycle    • History loading                 │ ║
║  │  • Context assembly      • Transaction mgmt                │ ║
║  └──────────────────────┬─────────────────────────────────────┘ ║
║                         │                                       ║
║  ┌──────────────────────▼─────────────────────────────────────┐ ║
║  │             ToolCallOrchestrator                           │ ║
║  │  • Iterative LLM loop   • Tool execution                   │ ║
║  │  • Token tracking       • Error handling                   │ ║
║  └────────────────────────────────────────────────────────────┘ ║
║                                                                 ║
║  ┌──────────────────┐  ┌─────────────────┐  ┌──────────────┐    ║
║  │ ConfigLoader     │  │ InputProcessor  │  │ DocumentBld  │    ║
║  │ • Model setup    │  │ • Route cmd/msg │  │ • Context    │    ║
║  │ • Client init    │  │ • Thread spawn  │  │ • Tools fmt  │    ║
║  └──────────────────┘  └─────────────────┘  └──────────────┘    ║
╚═════════════════════════════════════════════════════════════════╝
         │                    │                    │
         ▼                    ▼                    ▼
╔════════════════════╗  ╔═══════════════╗  ╔═══════════════════╗
║   CLIENT LAYER     ║  ║  TOOL SYSTEM  ║  ║   MEMORY & RAG    ║
╠════════════════════╣  ╠═══════════════╣  ╠═══════════════════╣
║ ClientFactory      ║  ║ ToolRegistry  ║  ║ RAGRetriever      ║
║                    ║  ║               ║  ║                   ║
║ ┌────────────────┐ ║  ║ 23 Tools:     ║  ║ Chain of Resp:    ║
║ │ Anthropic      │ ║  ║ • file_*      ║  ║ 1. QueryEmbed     ║
║ │ • Claude       │ ║  ║ • dir_*       ║  ║ 2. ConvSearch     ║
║ └────────────────┘ ║  ║ • execute_*   ║  ║ 3. ExchSearch     ║
║ ┌────────────────┐ ║  ║ • database_*  ║  ║ 4. ContextFmt     ║
║ │ Google         │ ║  ║ • search_*    ║  ║                   ║
║ │ • Gemini       │ ║  ║               ║  ║ EmbeddingStore    ║
║ └────────────────┘ ║  ║ Tool Schema:  ║  ║ • VSS/HNSW        ║
║ ┌────────────────┐ ║  ║ • name        ║  ║ • Similarity      ║
║ │ OpenAI         │ ║  ║ • description ║  ║ • FLOAT[1536]     ║
║ │ • GPT          │ ║  ║ • params      ║  ║                   ║
║ │ • Embeddings   │ ║  ║ • execute()   ║  ║ RAGContext        ║
║ └────────────────┘ ║  ║               ║  ║ • Conversations   ║
║ ┌────────────────┐ ║  ║ Edit Ops:     ║  ║ • Exchanges       ║
║ │ xAI            │ ║  ║ 8 operations  ║  ║ • Formatted doc   ║
║ │ • Grok         │ ║  ║ • append      ║  ║                   ║
║ └────────────────┘ ║  ║ • prepend     ║  ║ Config:           ║
║                    ║  ║ • insert_*    ║  ║ • exch/conv count ║
║ Unified API:       ║  ║ • replace_*   ║  ║ • similarity      ║
║ • send_message()   ║  ║               ║  ║ • capacity        ║
║ • format_tools()   ║  ║               ║  ║                   ║
║ • calculate_cost() ║  ║               ║  ║                   ║
╚════════════════════╝  ╚═══════════════╝  ╚═══════════════════╝
         │                      │                     │
         └──────────────────────┼─────────────────────┘
                                │
                    ╔═══════════▼════════════╗
                    ║   DATABASE LAYER       ║
                    ╠════════════════════════╣
                    ║ History                ║
                    ║ • Connection pool      ║
                    ║ • Transaction mgmt     ║
                    ║                        ║
                    ║ Repositories:          ║
                    ║ • MessageRepository    ║
                    ║ • ConversationRepo     ║
                    ║ • ExchangeRepository   ║
                    ║ • EmbeddingStore       ║
                    ║ • ConfigStore          ║
                    ║                        ║
                    ║ Schema Management:     ║
                    ║ • SchemaManager        ║
                    ║ • MigrationManager     ║
                    ║                        ║
                    ║ DuckDB:                ║
                    ║ • WAL mode             ║
                    ║ • VSS extension        ║
                    ║ • Thread-safe pool     ║
                    ╚════════════════════════╝
                                │
                    ╔═══════════▼════════════╗
                    ║   WORKER SUBSYSTEM     ║
                    ╠════════════════════════╣
                    ║ BackgroundWorkerMgr    ║
                    ║ • Start/stop/pause     ║
                    ║ • Status tracking      ║
                    ║                        ║
                    ║ Workers (PausableTask):║
                    ║ ┌────────────────────┐ ║
                    ║ │ ConvSummarizer     │ ║
                    ║ │ • LLM summaries    │ ║
                    ║ └────────────────────┘ ║
                    ║ ┌────────────────────┐ ║
                    ║ │ ExchSummarizer     │ ║
                    ║ │ • Exchange sums    │ ║
                    ║ └────────────────────┘ ║
                    ║ ┌────────────────────┐ ║
                    ║ │ EmbedGenerator     │ ║
                    ║ │ • Batch embed      │ ║
                    ║ │ • Rate limiting    │ ║
                    ║ └────────────────────┘ ║
                    ║                        ║
                    ║ WorkerToken:           ║
                    ║ • Pause coordination   ║
                    ║ • Critical sections    ║
                    ╚════════════════════════╝
```

---

## Level 3: Subsystem Deep Dives

### 3.1 CLI Layer Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         ConsoleIO                                │
│                   (console_io.rb)                                │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────────┐    │
│  │  Input System  │  │ Output System  │  │  Spinner System  │    │
│  │                │  │                │  │                  │    │
│  │ • Raw mode     │  │ • Queue-based  │  │ • Animation loop │    │
│  │ • IO.select    │  │ • Thread-safe  │  │ • Background out │    │
│  │ • readline-like│  │ • Mutex sync   │  │ • Status msgs    │    │
│  │ • History nav  │  │ • Flush ctrl   │  │                  │    │
│  │ • Ctrl-C       │  │                │  │                  │    │
│  └────────────────┘  └────────────────┘  └──────────────────┘    │
│                                                                  │
│  Input Flow:                                                     │
│  User keystroke → read_nonblock → build line → Enter             │
│        ↓                ↓              ↓           ↓             │
│   Ctrl chars    Backspace/Del    Arrow keys    Return input      │
│                                                                  │
│  Output Flow:                                                    │
│  puts() → Queue → flush_queue → Write to stdout                  │
│                                                                  │
│  Spinner Flow:                                                   │
│  start_spinner → Thread loop → animate frames → stop_spinner     │
│      ↓                              ↓                 ↓          │
│  Set status              Write frame + text     Clear line       │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

```
┌──────────────────────────────────────────────────────────────────┐
│                      Command System                              │
│                   (commands/ directory)                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │               CommandRegistry                            │    │
│  │  • Register commands                                     │    │
│  │  • Route /command to handler                             │    │
│  │  • List available commands                               │    │
│  └──────────────────────────────────────────────────────────┘    │
│                           │                                      │
│                           │ inherits from                        │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │               BaseCommand                                │    │
│  │  • name, description, usage                              │    │
│  │  • execute(args, context)                                │    │
│  │  • validate_args()                                       │    │
│  └──────────────────────────────────────────────────────────┘    │
│                           │                                      │
│            ┌──────────────┴──────────────┐                       │
│            ▼                             ▼                       │
│  ┌──────────────────┐         ┌──────────────────┐               │
│  │ Simple Commands  │         │ Complex Commands │               │
│  │                  │         │                  │               │
│  │ /help            │         │ /models          │               │
│  │ /info            │         │ • list           │               │
│  │ /history         │         │ • show           │               │
│  │ /tools           │         │ • set            │               │
│  │ /version         │         │                  │               │
│  │ /exit            │         │ /rag             │               │
│  │                  │         │ • status         │               │
│  │                  │         │ • config         │               │
│  │                  │         │                  │               │
│  │                  │         │ /worker          │               │
│  │                  │         │ • status         │               │
│  │                  │         │ • pause/resume   │               │
│  │                  │         │ • start/stop     │               │
│  │                  │         │                  │               │
│  │                  │         │ /backup          │               │
│  │                  │         │ • Validation     │               │
│  │                  │         │ • Progress       │               │
│  │                  │         │ • Worker coord   │               │
│  └──────────────────┘         └──────────────────┘               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

```
┌──────────────────────────────────────────────────────────────────┐
│                      Formatter System                            │
│                   (formatter.rb + formatters/)                   │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │               Formatter (Main)                           │    │
│  │  • format_message(msg) - Route by role                   │    │
│  │  • format_token_stats(metrics)                           │    │
│  │  • Debug output control (VERBOSE, VERY_VERBOSE)          │    │
│  └────────────────────┬─────────────────────────────────────┘    │
│                       │ delegates to                             │
│       ┌───────────────┼───────────────┐                          │
│       ▼               ▼               ▼                          │
│  ┌─────────┐  ┌──────────────┐  ┌─────────────────┐              │
│  │ ToolCall│  │ ToolResult   │  │ LlmRequest      │              │
│  │Formatter│  │ Formatter    │  │ Formatter       │              │
│  │         │  │              │  │                 │              │
│  │ • Name  │  │ • Name       │  │ • Model         │              │
│  │ • Args  │  │ • Status     │  │ • Input tokens  │              │
│  │ • Pretty│  │ • Output     │  │ • Tools         │              │
│  │  print  │  │ • Truncate   │  │ • System prompt │              │
│  └─────────┘  └──────────────┘  └─────────────────┘              │
│                                                                  │
│  Message Types:                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ user      → "User: <content>"                              │  │
│  │ assistant → "<content>"                                    │  │
│  │ tool      → Delegate to ToolCallFormatter                  │  │
│  │ result    → Delegate to ToolResultFormatter                │  │
│  │ system    → Debug only (VERY_VERBOSE)                      │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Token Statistics Format:                                        │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Input: 1,234 tokens | Output: 567 tokens                   │  │
│  │ Cost: $0.0123 | Total this exchange: $0.0456               │  │
│  │ Tool calls: 3 | Final answer: true                         │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 3.2 Agent Core - Orchestration

```
┌─────────────────────────────────────────────────────────────────┐
│              ChatLoopOrchestrator Architecture                  │
│                  (chat_loop_orchestrator.rb)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Lifecycle:                                                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ 1. process_user_message(content)                          │  │
│  │    ↓                                                      │  │
│  │ 2. Acquire WorkerToken (pause background workers)         │  │
│  │    ↓                                                      │  │
│  │ 3. Begin Database Transaction                             │  │
│  │    ↓                                                      │  │
│  │ 4. Create Exchange record                                 │  │
│  │    ↓                                                      │  │
│  │ 5. Save user message                                      │  │
│  │    ↓                                                      │  │
│  │ 6. Build context document                                 │  │
│  │    ├─ Load message history                                │  │
│  │    ├─ Retrieve RAG context (vector search)                │  │
│  │    ├─ Format tool definitions                             │  │
│  │    └─ Add user query                                      │  │
│  │    ↓                                                      │  │
│  │ 7. Delegate to ToolCallOrchestrator                       │  │
│  │    └─ Iterative LLM loop with tool execution              │  │
│  │    ↓                                                      │  │
│  │ 8. Save metrics to exchange                               │  │
│  │    ↓                                                      │  │
│  │ 9. Commit Transaction                                     │  │
│  │    ↓                                                      │  │
│  │ 10. Release WorkerToken (resume workers)                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Error Handling:                                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ rescue Exception                                          │  │
│  │   ├─ Rollback transaction                                 │  │
│  │   ├─ Release worker token                                 │  │
│  │   ├─ Log error                                            │  │
│  │   └─ Re-raise                                             │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Context Document Structure:                                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ # Context for AI Assistant                                │  │
│  │                                                           │  │
│  │ ## Conversation History                                   │  │
│  │ [Last N messages from current conversation]               │  │
│  │                                                           │  │
│  │ ## Related Information from Memory (RAG)                  │  │
│  │ [Vector search results - conversations & exchanges]       │  │
│  │                                                           │  │
│  │ ## Available Tools                                        │  │
│  │ [Tool definitions in provider-specific format]            │  │
│  │                                                           │  │
│  │ ## User Query                                             │  │
│  │ [Current user input]                                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────┐
│              ToolCallOrchestrator Architecture                  │
│                  (tool_call_orchestrator.rb)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Main Loop:                                                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ process_with_tools(messages, exchange_id)                 │  │
│  │                                                           │  │
│  │ loop do                                                   │  │
│  │   │                                                       │  │
│  │   1. LLM Request                                          │  │
│  │      ├─ Send messages + tools                             │  │
│  │      ├─ Track tokens                                      │  │
│  │      └─ Calculate cost                                    │  │
│  │      ↓                                                    │  │
│  │   2. Check Response Type                                  │  │
│  │      │                                                    │  │
│  │      ├─ Text only? → Final answer, break                  │  │
│  │      │                                                    │  │
│  │      └─ Tool calls? ↓                                     │  │
│  │         │                                                 │  │
│  │   3. Execute Tools (parallel)                             │  │
│  │      ├─ For each tool call:                               │  │
│  │      │   ├─ Validate tool exists                          │  │
│  │      │   ├─ Execute tool.execute()                        │  │
│  │      │   ├─ Capture result/error                          │  │
│  │      │   └─ Redact sensitive data                         │  │
│  │      │                                                    │  │
│  │   4. Save Messages                                        │  │
│  │      ├─ Save assistant message (with tool calls)          │  │
│  │      ├─ Save tool results (redacted)                      │  │
│  │      └─ Append to messages array                          │  │
│  │      ↓                                                    │  │
│  │   5. Continue loop (next LLM request)                     │  │
│  │      │                                                    │  │
│  │ end                                                       │  │
│  │   ↓                                                       │  │
│  │ Return metrics:                                           │  │
│  │   • total_input_tokens                                    │  │
│  │   • total_output_tokens                                   │  │
│  │   • total_cost                                            │  │
│  │   • tool_call_count                                       │  │
│  │   • request_count                                         │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Tool Execution Details:                                        │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ execute_tool(name, args, context)                         │  │
│  │   ↓                                                       │  │
│  │ 1. Look up tool in registry                               │  │
│  │ 2. Call tool.execute(args, context)                       │  │
│  │    Context includes:                                      │  │
│  │    • history (db access)                                  │  │
│  │    • conversation_id                                      │  │
│  │    • model info                                           │  │
│  │    • tool_registry                                        │  │
│  │ 3. Return result or error                                 │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Metrics Tracking:                                              │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Accumulated per exchange:                                 │  │
│  │ • Input tokens:  Sum of all requests                      │  │
│  │ • Output tokens: Sum of all responses                     │  │
│  │ • Cost:          Calculated via client.calculate_cost()   │  │
│  │ • Tool calls:    Count of tool executions                 │  │
│  │ • Requests:      Count of LLM API calls                   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.3 Tool System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      ToolRegistry                               │
│                   (tool_registry.rb)                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Registration:                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ register_tool(tool_class)                                 │  │
│  │   ↓                                                       │  │
│  │ @tools[tool.name] = tool.new                              │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Formatting (Provider-Specific):                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ format_for_anthropic() → Anthropic tool schema            │  │
│  │ format_for_google()    → Google function schema           │  │
│  │ format_for_openai()    → OpenAI function schema           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Execution:                                                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ execute(name, args, context)                              │  │
│  │   ↓                                                       │  │
│  │ tool = @tools[name]                                       │  │
│  │ tool.execute(args, context)                               │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   Tool Implementation Pattern                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  class MyTool                                                   │
│    def self.name → String                                       │
│    def self.description → String                                │
│    def self.parameters → Hash (JSON Schema)                     │
│    def execute(args, context) → String                          │
│  end                                                            │
│                                                                 │
│  Context Hash Contains:                                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ {                                                         │  │
│  │   history:          History instance (db access)          │  │
│  │   conversation_id:  Current conversation                  │  │
│  │   model:            LLM model name                        │  │
│  │   tool_registry:    Access to other tools                 │  │
│  │ }                                                         │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      23 Built-in Tools                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  File Operations (11 tools):                                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ file_read        → Read file contents                     │  │
│  │ file_write       → Write/overwrite file                   │  │
│  │ file_edit        → Edit with 8 operations:                │  │
│  │   ├─ append          (add to end)                         │  │
│  │   ├─ prepend         (add to start)                       │  │
│  │   ├─ insert_after    (after pattern)                      │  │
│  │   ├─ insert_before   (before pattern)                     │  │
│  │   ├─ insert_line     (at line number)                     │  │
│  │   ├─ replace         (pattern → new)                      │  │
│  │   ├─ replace_line    (line # → new)                       │  │
│  │   └─ replace_range   (lines N-M → new)                    │  │
│  │ file_copy        → Copy file                              │  │
│  │ file_move        → Move/rename file                       │  │
│  │ file_delete      → Delete file                            │  │
│  │ file_stat        → File metadata                          │  │
│  │ file_glob        → Find files by pattern                  │  │
│  │ file_grep        → Search file contents (ripgrep)         │  │
│  │ file_tree        → Directory tree view                    │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Directory Operations (3 tools):                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ dir_list         → List directory contents                │  │
│  │ dir_create       → Create directory                       │  │
│  │ dir_delete       → Delete directory                       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Execution Tools (2 tools):                                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ execute_bash     → Run bash commands                      │  │
│  │ execute_python   → Run Python scripts                     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Database Tools (4 tools):                                      │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ database_query   → Execute SQL queries                    │  │
│  │ database_schema  → Show table schema                      │  │
│  │ database_tables  → List all tables                        │  │
│  │ database_message → Query message history                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Internet Tools (1 tool):                                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ search_internet  → Web search                             │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Meta Tools (1 tool):                                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ agent_summarizer → Summarize conversations/exchanges      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.4 Memory & RAG System

```
┌─────────────────────────────────────────────────────────────────┐
│                  Hierarchical Memory Model                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Conversations (Top Level)                     │ │
│  │  • id: UUID                                                │ │
│  │  • created_at, updated_at: timestamps                      │ │
│  │  • summary: LLM-generated overview (2-3 sentences)         │ │
│  │  • model_name: Primary model used                          │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │              ↓ has many                                    │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │              Exchanges (User Query + Response)             │ │
│  │  • id: UUID                                                │ │
│  │  • conversation_id: Foreign key                            │ │
│  │  • created_at, updated_at: timestamps                      │ │
│  │  • summary: LLM-generated (user intent + outcome)          │ │
│  │  • Metrics:                                                │ │
│  │    - total_input_tokens                                    │ │
│  │    - total_output_tokens                                   │ │
│  │    - total_cost                                            │ │
│  │    - tool_call_count                                       │ │
│  │    - request_count                                         │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │              ↓ has many                                    │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │              Messages (Individual Turns)                   │ │
│  │  • id: UUID                                                │ │
│  │  • exchange_id: Foreign key                                │ │
│  │  • role: user, assistant, tool, tool_result, system        │ │
│  │  • content: Message text/JSON                              │ │
│  │  • content_redacted: Sanitized version (for display)       │ │
│  │  • timestamp: When created                                 │ │
│  │  • tool_call_id, tool_name: For tool messages              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Embeddings (Separate Table):                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │           text_embedding_3_small                           │ │
│  │  • id: Reference to conversation/exchange                  │ │
│  │  • embedding: FLOAT[1536] (OpenAI embedding)               │ │
│  │  • text: Original summary text                             │ │
│  │  • type: 'conversation' or 'exchange'                      │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  RAG Retrieval Pipeline                         │
│                   (Chain of Responsibility)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Step 1: RAGRetriever (Pipeline Orchestrator)             │   │
│  │  • retrieve(query, conversation_id, model) → RAGContext  │   │
│  │  • Builds processor chain                                │   │
│  │  • Executes processors in sequence                       │   │
│  └──────────────┬───────────────────────────────────────────┘   │
│                 │                                               │
│                 ▼                                               │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Step 2: QueryEmbeddingProcessor                          │   │
│  │  • Generate embedding for user query                     │   │
│  │  • Uses OpenAI text-embedding-3-small                    │   │
│  │  • Output: FLOAT[1536] vector                            │   │
│  │  • Store in context.query_embedding                      │   │
│  └──────────────┬───────────────────────────────────────────┘   │
│                 │                                               │
│                 ▼                                               │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Step 3: ConversationSearchProcessor                      │   │
│  │  • Search conversation summaries via vector similarity   │   │
│  │  • Exclude current conversation                          │   │
│  │  • Filter by similarity threshold (default: 0.7)         │   │
│  │  • Limit results (default: 3)                            │   │
│  │  • Uses VSS (HNSW index) if available                    │   │
│  │  • Falls back to linear scan if VSS unavailable          │   │
│  │  • Store in context.conversations                        │   │
│  └──────────────┬───────────────────────────────────────────┘   │
│                 │                                               │
│                 ▼                                               │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Step 4: ExchangeSearchProcessor                          │   │
│  │  • Search exchange summaries via vector similarity       │   │
│  │  • Search within found conversations + current           │   │
│  │  • Filter by similarity threshold                        │   │
│  │  • Limit results per conversation (default: 10)          │   │
│  │  • Store in context.exchanges                            │   │
│  └──────────────┬───────────────────────────────────────────┘   │
│                 │                                               │
│                 ▼                                               │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Step 5: ContextFormatterProcessor                        │   │
│  │  • Format results as markdown                            │   │
│  │  • Structure:                                            │   │
│  │    ## Related Conversations                              │   │
│  │    - Conversation 1 summary                              │   │
│  │    - Conversation 2 summary                              │   │
│  │                                                          │   │
│  │    ## Relevant Exchanges                                 │   │
│  │    ### From Conversation 1                               │   │
│  │    - Exchange 1 summary                                  │   │
│  │    - Exchange 2 summary                                  │   │
│  │                                                          │   │
│  │  • Store in context.formatted_context                    │   │
│  └──────────────┬───────────────────────────────────────────┘   │
│                 │                                               │
│                 ▼                                               │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Output: RAGContext                                       │   │
│  │  • query_embedding: FLOAT[1536]                          │   │
│  │  • conversations: Array of matching conversations        │   │
│  │  • exchanges: Array of matching exchanges                │   │
│  │  • formatted_context: Markdown string                    │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  Vector Search Implementation                   │
│                   (EmbeddingStore)                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Storage:                                                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ DuckDB Table: text_embedding_3_small                      │  │
│  │ Columns:                                                  │  │
│  │  • id (VARCHAR)       - conversation/exchange UUID        │  │
│  │  • embedding (FLOAT[1536]) - Vector                       │  │
│  │  • text (VARCHAR)     - Original summary                  │  │
│  │  • type (VARCHAR)     - 'conversation' or 'exchange'      │  │
│  │                                                           │  │
│  │ Index: HNSW (if VSS extension available)                  │  │
│  │  • M = 16 (connections per layer)                         │  │
│  │  • ef_construction = 128                                  │  │
│  │  • ef_search = 64                                         │  │
│  │  • Metric: cosine distance                                │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Search Algorithm:                                              │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ IF VSS available:                                         │  │
│  │   Use HNSW index for approximate nearest neighbor         │  │
│  │   Fast: O(log N) average case                             │  │
│  │ ELSE:                                                     │  │
│  │   Linear scan with cosine similarity                      │  │
│  │   Slower: O(N) but works without extension                │  │
│  │                                                           │  │
│  │ Cosine Similarity:                                        │  │
│  │   similarity = dot(A, B) / (norm(A) * norm(B))            │  │
│  │   Range: [-1, 1], higher = more similar                   │  │
│  │                                                           │  │
│  │ Filtering:                                                │  │
│  │   • threshold: minimum similarity (default 0.7)           │  │
│  │   • limit: max results to return                          │  │
│  │   • exclude: filter out specific IDs                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Configuration (stored in appconfig):                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ rag.exchanges_per_conversation (default: 3)               │  │
│  │ rag.exchange_capacity (default: 10)                       │  │
│  │ rag.similarity_threshold (default: 0.7)                   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.5 Multi-LLM Client Layer

```
┌─────────────────────────────────────────────────────────────────┐
│                      ClientFactory Pattern                      │
│                   (client_factory.rb)                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  create(model_name, options = {})                               │
│    ↓                                                            │
│  Detect provider from model name prefix/pattern                 │
│    ↓                                                            │
│  ┌──────────────┬──────────────┬──────────────┬─────────────┐   │
│  │  claude-*    │   gemini-*   │    gpt-*     │   grok-*    │   │
│  │      ↓       │       ↓      │       ↓      │      ↓      │   │
│  │  Anthropic   │    Google    │   OpenAI     │    xAI      │   │
│  └──────────────┴──────────────┴──────────────┴─────────────┘   │
│                                                                 │
│  Unified Client Interface:                                      │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ send_message(messages:, tools:, **options)                │  │
│  │   → { content:, tool_calls:, stop_reason: }               │  │
│  │                                                           │  │
│  │ format_tools(tool_registry)                               │  │
│  │   → Provider-specific tool schema                         │  │
│  │                                                           │  │
│  │ calculate_cost(input_tokens:, output_tokens:)             │  │
│  │   → Float (USD)                                           │  │
│  │                                                           │  │
│  │ max_context                                               │  │
│  │   → Integer (token limit)                                 │  │
│  │                                                           │  │
│  │ model_name                                                │  │
│  │   → String                                                │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    Provider Implementations                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Anthropic Client (clients/anthropic.rb)                   │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ Models:                                                   │  │
│  │  • claude-haiku-4-5   ($0.40/$2.00 per 1M tokens)         │  │
│  │  • claude-sonnet-4-5  ($1.50/$7.50)                       │  │
│  │  • claude-opus-4-1    ($7.50/$37.50)                      │  │
│  │                                                           │  │
│  │ Context: 200,000 tokens                                   │  │
│  │                                                           │  │
│  │ API Format:                                               │  │
│  │  • Messages API                                           │  │
│  │  • Native tool use (function calling)                     │  │
│  │  • System prompt support                                  │  │
│  │  • Streaming support                                      │  │
│  │                                                           │  │
│  │ Tool Format:                                              │  │
│  │  { name:, description:, input_schema: }                   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Google Client (clients/google.rb)                         │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ Models:                                                   │  │
│  │  • gemini-2.5-flash-lite  (0k context, cheapest)          │  │
│  │  • gemini-2.5-flash       (1M context)                    │  │
│  │  • gemini-2.5-pro         (2M context, most capable)      │  │
│  │                                                           │  │
│  │ API Format:                                               │  │
│  │  • Gemini API                                             │  │
│  │  • Function declarations                                  │  │
│  │  • System instructions                                    │  │
│  │                                                           │  │
│  │ Tool Format:                                              │  │
│  │  { name:, description:, parameters: }                     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ OpenAI Client (clients/openai.rb)                         │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ Models:                                                   │  │
│  │  • gpt-5-nano-2025-08-07  (Fast, cheap)                   │  │
│  │  • gpt-5-mini             (Balanced)                      │  │
│  │  • gpt-5                  (Most capable)                  │  │
│  │                                                           │  │
│  │ Context: Varies by model                                  │  │
│  │                                                           │  │
│  │ API Format:                                               │  │
│  │  • Chat Completions API                                   │  │
│  │  • Function calling                                       │  │
│  │  • System messages                                        │  │
│  │                                                           │  │
│  │ Tool Format:                                              │  │
│  │  { type: "function",                                      │  │
│  │    function: { name:, description:, parameters: } }       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ xAI Client (clients/xai.rb)                               │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ Models:                                                   │  │
│  │  • grok-3           (General purpose)                     │  │
│  │  • grok-code-fast-1 (Code-focused)                        │  │
│  │                                                           │  │
│  │ API: OpenAI-compatible                                    │  │
│  │      (uses OpenAI client with xAI base URL)               │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ OpenAI Embeddings (clients/openai_embeddings.rb)          │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ Model: text-embedding-3-small                             │  │
│  │  • Dimensions: 1536                                       │  │
│  │  • Cost: $0.02 per 1M tokens                              │  │
│  │  • Batch support (up to 100 texts)                        │  │
│  │                                                           │  │
│  │ Usage:                                                    │  │
│  │  embed(text) → FLOAT[1536]                                │  │
│  │  embed_batch(texts[]) → Array of vectors                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  Message Format Translation                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Internal Format (Database):                                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ {                                                         │  │
│  │   role: "user" | "assistant" | "tool" | "tool_result",    │  │
│  │   content: "text or JSON",                                │  │
│  │   tool_call_id: "uuid" (for tool messages),               │  │
│  │   tool_name: "name" (for tool messages)                   │  │
│  │ }                                                         │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Each client translates to/from provider-specific formats       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.6 Database Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     History (Main Interface)                    │
│                        (history.rb)                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Thread-Safe Connection Pool:                                   │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ @connections = {}  # Hash of Thread → DuckDB::Database    │ │
│  │ @mutex = Mutex.new                                        │ │
│  │                                                            │ │
│  │ connection                                                 │ │
│  │   ├─ Check @connections[Thread.current]                   │ │
│  │   ├─ Create new if missing (synchronized)                 │ │
│  │   └─ Return per-thread connection                         │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Transaction Support:                                           │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ transaction do |txn|                                      │ │
│  │   # Work here                                             │ │
│  │   txn.commit   # Explicit commit                          │ │
│  │   # or                                                     │ │
│  │   txn.rollback # Explicit rollback                        │ │
│  │ end                                                        │ │
│  │                                                            │ │
│  │ Automatic rollback on exceptions                          │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Repository Delegation:                                         │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ conversations → ConversationRepository                    │ │
│  │ exchanges     → ExchangeRepository                        │ │
│  │ messages      → MessageRepository                         │ │
│  │ embeddings    → EmbeddingStore                            │ │
│  │ config        → ConfigStore                               │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Lifecycle:                                                     │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ initialize(db_path, options)                              │ │
│  │   ├─ Create database file                                 │ │
│  │   ├─ Initialize schema (SchemaManager)                    │ │
│  │   ├─ Run migrations (MigrationManager)                    │ │
│  │   ├─ Load VSS extension if available                      │ │
│  │   └─ Create repositories                                  │ │
│  │                                                            │ │
│  │ close                                                      │ │
│  │   ├─ Critical section (acquire mutex)                     │ │
│  │   ├─ Close all thread connections                         │ │
│  │   └─ Release mutex                                        │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  Repository Pattern Architecture                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ ConversationRepository (conversation_repository.rb)       │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │ • create(model_name) → conversation_id                    │ │
│  │ • find(id) → conversation hash                            │ │
│  │ • update_summary(id, summary)                             │ │
│  │ • all → array of conversations                            │ │
│  │ • current → most recent conversation                      │ │
│  │ • count → total conversations                             │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ ExchangeRepository (exchange_repository.rb)               │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │ • create(conversation_id) → exchange_id                   │ │
│  │ • find(id) → exchange hash                                │ │
│  │ • update_summary(id, summary)                             │ │
│  │ • update_metrics(id, metrics_hash)                        │ │
│  │ • by_conversation(conv_id) → exchanges array              │ │
│  │ • unsummarized → exchanges without summaries              │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ MessageRepository (message_repository.rb)                 │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │ • create(exchange_id, role, content, **options)           │ │
│  │ • find(id) → message hash                                 │ │
│  │ • by_exchange(exchange_id) → messages array               │ │
│  │ • by_conversation(conv_id, limit) → messages array        │ │
│  │ • update_redacted(id, content_redacted)                   │ │
│  │ • delete(id)                                              │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ EmbeddingStore (embedding_store.rb)                       │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │ • upsert(id, embedding, text, type)                       │ │
│  │ • find(id) → embedding hash                               │ │
│  │ • search(query_embedding, options) → results array        │ │
│  │ • search_by_type(type, query_embedding, options)          │ │
│  │ • delete(id)                                              │ │
│  │ • vss_available? → boolean                                │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ ConfigStore (config_store.rb)                             │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │ • get(key, default = nil) → value                         │ │
│  │ • set(key, value)                                         │ │
│  │ • delete(key)                                             │ │
│  │ • all → hash of all config                                │ │
│  │                                                            │ │
│  │ Stored Configuration:                                      │ │
│  │  • current_model                                          │ │
│  │  • rag.exchanges_per_conversation                         │ │
│  │  • rag.exchange_capacity                                  │ │
│  │  • rag.similarity_threshold                               │ │
│  │  • worker.conversation_summarizer.enabled                 │ │
│  │  • worker.exchange_summarizer.enabled                     │ │
│  │  • worker.embedding_generator.enabled                     │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      Database Schema                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  conversations                                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ id              VARCHAR   PRIMARY KEY                      │ │
│  │ created_at      TIMESTAMP NOT NULL                         │ │
│  │ updated_at      TIMESTAMP NOT NULL                         │ │
│  │ summary         TEXT                                       │ │
│  │ model_name      VARCHAR   NOT NULL                         │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  exchanges                                                      │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ id                   VARCHAR   PRIMARY KEY                 │ │
│  │ conversation_id      VARCHAR   NOT NULL (FK)               │ │
│  │ created_at           TIMESTAMP NOT NULL                    │ │
│  │ updated_at           TIMESTAMP NOT NULL                    │ │
│  │ summary              TEXT                                  │ │
│  │ total_input_tokens   INTEGER                               │ │
│  │ total_output_tokens  INTEGER                               │ │
│  │ total_cost           REAL                                  │ │
│  │ tool_call_count      INTEGER                               │ │
│  │ request_count        INTEGER                               │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  messages                                                       │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ id               VARCHAR   PRIMARY KEY                     │ │
│  │ exchange_id      VARCHAR   NOT NULL (FK)                   │ │
│  │ role             VARCHAR   NOT NULL                        │ │
│  │ content          TEXT      NOT NULL                        │ │
│  │ content_redacted TEXT                                      │ │
│  │ timestamp        TIMESTAMP NOT NULL                        │ │
│  │ tool_call_id     VARCHAR                                   │ │
│  │ tool_name        VARCHAR                                   │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  text_embedding_3_small                                         │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ id        VARCHAR    PRIMARY KEY                           │ │
│  │ embedding FLOAT[1536] NOT NULL                             │ │
│  │ text      TEXT       NOT NULL                              │ │
│  │ type      VARCHAR    NOT NULL                              │ │
│  │                                                             │ │
│  │ INDEX: HNSW on embedding (if VSS available)                │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  appconfig                                                      │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ key   VARCHAR PRIMARY KEY                                  │ │
│  │ value TEXT    NOT NULL                                     │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  command_history                                                │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ id        INTEGER  PRIMARY KEY                             │ │
│  │ command   TEXT     NOT NULL                                │ │
│  │ timestamp TIMESTAMP NOT NULL                               │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  migrations                                                     │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ version   INTEGER  PRIMARY KEY                             │ │
│  │ applied_at TIMESTAMP NOT NULL                              │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  DuckDB Configuration:                                          │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ • WAL mode: ON (write-ahead logging for durability)       │ │
│  │ • VSS extension: ~/.local/lib/vss.duckdb_extension        │ │
│  │ • Auto-recovery on startup (WAL replay)                   │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.7 Background Worker System

```
┌─────────────────────────────────────────────────────────────────┐
│              BackgroundWorkerManager                            │
│            (background_worker_manager.rb)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Worker Lifecycle:                                              │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ initialize(history)                                       │ │
│  │   ├─ Create 3 workers:                                    │ │
│  │   │   • ConversationSummarizer                            │ │
│  │   │   • ExchangeSummarizer                                │ │
│  │   │   • EmbeddingGenerator                                │ │
│  │   ├─ Load config from database                            │ │
│  │   └─ Don't start yet (explicit start_all)                 │ │
│  │                                                            │ │
│  │ start_all                                                  │ │
│  │   ├─ Start each worker thread                             │ │
│  │   └─ Set @running = true                                  │ │
│  │                                                            │ │
│  │ stop_all                                                   │ │
│  │   ├─ Signal shutdown to all workers                       │ │
│  │   ├─ Wait for threads to complete                         │ │
│  │   └─ Set @running = false                                 │ │
│  │                                                            │ │
│  │ pause_all                                                  │ │
│  │   └─ Each worker.pause                                    │ │
│  │                                                            │ │
│  │ resume_all                                                 │ │
│  │   └─ Each worker.resume                                   │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Status Tracking:                                               │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ status → Hash                                             │ │
│  │   {                                                        │ │
│  │     conversation_summarizer: {                            │ │
│  │       running: true/false,                                │ │
│  │       paused: true/false,                                 │ │
│  │       enabled: true/false                                 │ │
│  │     },                                                     │ │
│  │     exchange_summarizer: { ... },                         │ │
│  │     embedding_generator: { ... }                          │ │
│  │   }                                                        │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  PausableTask Base Class                        │
│                   (pausable_task.rb)                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  State Management:                                              │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ @running = false     # Worker thread active?              │ │
│  │ @paused = false      # Worker paused?                     │ │
│  │ @shutdown = false    # Shutdown signal received?          │ │
│  │ @mutex = Mutex.new   # State synchronization              │ │
│  │ @cv = ConditionVariable.new  # Wait/signal for pause      │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Main Loop Pattern:                                             │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ def run                                                    │ │
│  │   @running = true                                         │ │
│  │   loop do                                                  │ │
│  │     break if shutdown?                                    │ │
│  │     wait_if_paused                                        │ │
│  │     break if shutdown?  # Check again after wait          │ │
│  │                                                            │ │
│  │     perform_work  # Subclass implements this              │ │
│  │                                                            │ │
│  │     sleep(interval)                                       │ │
│  │   end                                                      │ │
│  │   @running = false                                        │ │
│  │ end                                                        │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Pause Coordination:                                            │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ pause                                                      │ │
│  │   @mutex.synchronize { @paused = true }                   │ │
│  │                                                            │ │
│  │ resume                                                     │ │
│  │   @mutex.synchronize do                                   │ │
│  │     @paused = false                                       │ │
│  │     @cv.signal  # Wake up waiting thread                  │ │
│  │   end                                                      │ │
│  │                                                            │ │
│  │ wait_if_paused                                            │ │
│  │   @mutex.synchronize do                                   │ │
│  │     @cv.wait(@mutex) while @paused && !@shutdown          │ │
│  │   end                                                      │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Shutdown Detection:                                            │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ shutdown?  # Check @shutdown flag                         │ │
│  │ stop       # Set @shutdown, signal condition variable     │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     Worker Implementations                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ ConversationSummarizer                                    │ │
│  │   (workers/conversation_summarizer.rb)                    │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │ Purpose: Generate summaries for completed conversations   │ │
│  │                                                            │ │
│  │ Algorithm:                                                 │ │
│  │ 1. Find conversations without summaries                   │ │
│  │    (exclude current conversation)                         │ │
│  │ 2. For each conversation:                                 │ │
│  │    a. Load all messages                                   │ │
│  │    b. Build prompt: "Summarize this conversation..."      │ │
│  │    c. Call LLM (configured summarizer model)              │ │
│  │    d. Check shutdown? after LLM call                      │ │
│  │    e. Update conversation.summary in database             │ │
│  │ 3. Sleep interval (default: 10 seconds)                   │ │
│  │                                                            │ │
│  │ Shutdown Awareness:                                        │ │
│  │ • Checks shutdown? before/after LLM calls                 │ │
│  │ • Gracefully exits if shutdown requested                  │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ ExchangeSummarizer                                        │ │
│  │   (workers/exchange_summarizer.rb)                        │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │ Purpose: Generate summaries for individual exchanges      │ │
│  │                                                            │ │
│  │ Algorithm:                                                 │ │
│  │ 1. Find exchanges without summaries                       │ │
│  │ 2. For each exchange:                                     │ │
│  │    a. Load exchange messages                              │ │
│  │    b. Build prompt: "Summarize what the user wanted..."   │ │
│  │    c. Call LLM (configured summarizer model)              │ │
│  │    d. Check shutdown? after LLM call                      │ │
│  │    e. Update exchange.summary in database                 │ │
│  │ 3. Sleep interval (default: 10 seconds)                   │ │
│  │                                                            │ │
│  │ Shutdown Awareness:                                        │ │
│  │ • Similar to ConversationSummarizer                       │ │
│  │ • Exits gracefully on shutdown signal                     │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ EmbeddingGenerator                                        │ │
│  │   (workers/embedding_generator.rb)                        │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │ Purpose: Generate embeddings for summaries                │ │
│  │                                                            │ │
│  │ Algorithm:                                                 │ │
│  │ 1. Find conversations with summaries but no embeddings    │ │
│  │ 2. Find exchanges with summaries but no embeddings        │ │
│  │ 3. Batch process (default: 10 items):                     │ │
│  │    a. Collect texts to embed                              │ │
│  │    b. Call OpenAI embeddings API (batch)                  │ │
│  │    c. Store embeddings in database                        │ │
│  │ 4. Rate limiting: sleep between batches (default: 100ms)  │ │
│  │ 5. Retry logic: exponential backoff on errors             │ │
│  │                                                            │ │
│  │ Configuration:                                             │ │
│  │ • batch_size: items per API call (default: 10)           │ │
│  │ • rate_limit_delay: ms between batches (default: 100)    │ │
│  │ • max_retries: retry attempts (default: 3)               │ │
│  │ • retry_delay: base delay in ms (default: 1000)          │ │
│  │                                                            │ │
│  │ Error Handling:                                            │ │
│  │ • Network errors: retry with backoff                      │ │
│  │ • Rate limits: exponential backoff                        │ │
│  │ • Permanent errors: log and skip                          │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  WorkerToken (Coordination)                     │
│                   (worker_token.rb)                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Purpose: Pause background workers during user interactions     │
│                                                                 │
│  Usage Pattern:                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ WorkerToken.acquire(worker_manager) do                    │ │
│  │   # Workers are paused here                               │ │
│  │   # Do work that needs database consistency               │ │
│  │ end                                                        │ │
│  │ # Workers automatically resumed                            │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Implementation:                                                │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ def self.acquire(manager)                                 │ │
│  │   manager.pause_all                                       │ │
│  │   yield                                                    │ │
│  │ ensure                                                     │ │
│  │   manager.resume_all                                      │ │
│  │ end                                                        │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Why This Matters:                                              │
│  • Prevents workers from interfering with user transactions     │
│  • Ensures clean database state during user interactions        │
│  • Automatic cleanup via ensure block                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Level 4: Key Interaction Flows

### 4.1 Complete User Query Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                  End-to-End Request Processing                  │
└─────────────────────────────────────────────────────────────────┘

USER TYPES: "Help me refactor the login function"
                         │
                         ▼
        ┌────────────────────────────────┐
        │   ConsoleIO.read_line          │
        │   • Raw terminal mode          │
        │   • Build input character-by-  │
        │     character                  │
        │   • Return on Enter            │
        └────────────┬───────────────────┘
                     │
                     ▼
        ┌────────────────────────────────┐
        │   InputProcessor.process       │
        │   • Check if slash command     │
        │   • Not a command, so spawn    │
        │     orchestrator thread        │
        └────────────┬───────────────────┘
                     │
                     ▼
        ┌────────────────────────────────┐
        │   Thread.new do                │
        │     orchestrator.process()     │
        │   end                          │
        └────────────┬───────────────────┘
                     │
        ╔════════════▼═══════════════════════════════════╗
        ║   IN ORCHESTRATOR THREAD (isolated)           ║
        ╚═══════════════════════════════════════════════╝
                     │
                     ▼
        ┌────────────────────────────────┐
        │ 1. Acquire WorkerToken         │
        │    • Pause all workers         │
        └────────────┬───────────────────┘
                     │
                     ▼
        ┌────────────────────────────────┐
        │ 2. Begin Transaction           │
        │    history.transaction do      │
        └────────────┬───────────────────┘
                     │
                     ▼
        ┌────────────────────────────────┐
        │ 3. Create Exchange Record      │
        │    exchange_id = SecureRandom  │
        │    .uuid                       │
        └────────────┬───────────────────┘
                     │
                     ▼
        ┌────────────────────────────────┐
        │ 4. Save User Message           │
        │    messages.create(            │
        │      exchange_id,              │
        │      role: 'user',             │
        │      content: input            │
        │    )                           │
        └────────────┬───────────────────┘
                     │
                     ▼
        ┌────────────────────────────────┐
        │ 5. Build Context Document      │
        ├────────────────────────────────┤
        │ a. Load message history        │
        │    messages = history.messages │
        │      .by_conversation(         │
        │        conversation_id,        │
        │        limit: 50               │
        │      )                         │
        │                                │
        │ b. RAG Retrieval               │
        │    rag_context = rag_retriever │
        │      .retrieve(                │
        │        query: input,           │
        │        conversation_id: id,    │
        │        model: current_model    │
        │      )                         │
        │    # Returns formatted md      │
        │                                │
        │ c. Format tool definitions     │
        │    tools = client.format_tools │
        │      (tool_registry)           │
        │                                │
        │ d. Assemble context doc        │
        │    document = <<~DOC           │
        │      # Context                 │
        │      ## History                │
        │      #{history_text}           │
        │      ## RAG Memory             │
        │      #{rag_context}            │
        │      ## Available Tools        │
        │      #{tools_list}             │
        │      ## User Query             │
        │      #{input}                  │
        │    DOC                         │
        └────────────┬───────────────────┘
                     │
                     ▼
        ┌────────────────────────────────────────────────┐
        │ 6. Delegate to ToolCallOrchestrator            │
        ├────────────────────────────────────────────────┤
        │ Loop:                                          │
        │   ┌─────────────────────────────────────────┐ │
        │   │ a. LLM Request                          │ │
        │   │    response = client.send_message(      │ │
        │   │      messages: messages,                │ │
        │   │      tools: tools                       │ │
        │   │    )                                    │ │
        │   │    # Track tokens, cost                 │ │
        │   │                                         │ │
        │   │ b. Check Response Type                  │ │
        │   │    if response[:tool_calls]             │ │
        │   │      # Execute tools                    │ │
        │   │      for tool_call in tool_calls        │ │
        │   │        result = registry.execute(       │ │
        │   │          tool_call[:name],              │ │
        │   │          tool_call[:args],              │ │
        │   │          context                        │ │
        │   │        )                                │ │
        │   │        # Save tool call message         │ │
        │   │        # Save tool result message       │ │
        │   │        messages << tool_result          │ │
        │   │      end                                │ │
        │   │      # Continue loop                    │ │
        │   │    else                                 │ │
        │   │      # Final text response              │ │
        │   │      break                              │ │
        │   │    end                                  │ │
        │   └─────────────────────────────────────────┘ │
        │                                                │
        │ Return metrics:                                │
        │   { total_input_tokens, total_output_tokens,   │
        │     total_cost, tool_call_count, ... }         │
        └────────────┬───────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────────────┐
        │ 7. Update Exchange Metrics     │
        │    exchanges.update_metrics(   │
        │      exchange_id,              │
        │      metrics                   │
        │    )                           │
        └────────────┬───────────────────┘
                     │
                     ▼
        ┌────────────────────────────────┐
        │ 8. Commit Transaction          │
        │    txn.commit                  │
        └────────────┬───────────────────┘
                     │
                     ▼
        ┌────────────────────────────────┐
        │ 9. Release WorkerToken         │
        │    • Resume workers            │
        └────────────┬───────────────────┘
                     │
        ╔════════════▼═══════════════════════════════════╗
        ║   BACK IN MAIN THREAD                         ║
        ╚═══════════════════════════════════════════════╝
                     │
                     ▼
        ┌────────────────────────────────┐
        │ 10. Format & Display Response  │
        │     formatter.format_message(  │
        │       assistant_message        │
        │     )                          │
        │     formatter.format_token_    │
        │       stats(metrics)           │
        │     console_io.puts(output)    │
        └────────────┬───────────────────┘
                     │
        ╔════════════▼═══════════════════════════════════╗
        ║   BACKGROUND WORKERS (resumed)                ║
        ╚═══════════════════════════════════════════════╝
                     │
        ┌────────────┴────────────┬────────────────────┐
        │                         │                    │
        ▼                         ▼                    ▼
┌────────────────┐  ┌────────────────┐  ┌─────────────────────┐
│ ConvSummarizer │  │ ExchSummarizer │  │ EmbedGenerator      │
│ • Find unsumm  │  │ • Find unsumm  │  │ • Find texts without│
│   conversations│  │   exchanges    │  │   embeddings        │
│ • Call LLM     │  │ • Call LLM     │  │ • Batch call OpenAI │
│ • Update DB    │  │ • Update DB    │  │ • Store vectors     │
└────────────────┘  └────────────────┘  └─────────────────────┘
```

### 4.2 Background Worker Coordination

```
┌─────────────────────────────────────────────────────────────────┐
│             Worker Pause/Resume Coordination                    │
└─────────────────────────────────────────────────────────────────┘

INITIAL STATE: Workers running in background

┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Worker 1   │  │  Worker 2   │  │  Worker 3   │
│  (running)  │  │  (running)  │  │  (running)  │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       │ Polling DB     │ Polling DB     │ Polling DB
       │ for work       │ for work       │ for work
       │                │                │

USER REQUEST ARRIVES
       │
       ▼
┌──────────────────┐
│ WorkerToken.     │
│ acquire()        │
└──────┬───────────┘
       │
       ├──────────────────────────────────────┐
       │                                      │
       ▼                                      ▼
┌──────────────────┐            ┌───────────────────────┐
│ worker_manager.  │            │ For each worker:      │
│ pause_all        │            │   worker.pause        │
└──────┬───────────┘            └───────┬───────────────┘
       │                                │
       │ Signals all workers            │
       │                                │
       ▼                                ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Worker 1   │  │  Worker 2   │  │  Worker 3   │
│  @paused=   │  │  @paused=   │  │  @paused=   │
│  true       │  │  true       │  │  true       │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       │ Reaches        │ Finishes       │ Currently
       │ wait_if_paused │ current work   │ sleeping
       │                │                │
       ▼                ▼                ▼
   BLOCKED          BLOCKED          BLOCKED
   (waiting on      (waiting on      (waiting on
    @cv)            @cv)             @cv)

┌──────────────────────────────────────────────┐
│ CRITICAL SECTION: User work happens here     │
│ • Transaction open                            │
│ • Database modifications                      │
│ • Tool execution                              │
│ • No worker interference                      │
└──────────────────┬───────────────────────────┘
                   │
                   ▼
         ┌─────────────────┐
         │ WorkerToken ends│
         │ (ensure block)  │
         └────────┬────────┘
                  │
                  ▼
         ┌─────────────────┐
         │ worker_manager. │
         │ resume_all      │
         └────────┬────────┘
                  │
       ┌──────────┼──────────┐
       │          │          │
       ▼          ▼          ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Worker 1   │  │  Worker 2   │  │  Worker 3   │
│  @paused=   │  │  @paused=   │  │  @paused=   │
│  false      │  │  false      │  │  false      │
│  @cv.signal │  │  @cv.signal │  │  @cv.signal │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       │ Wakes up       │ Wakes up       │ Wakes up
       │                │                │
       ▼                ▼                ▼
   RUNNING          RUNNING          RUNNING
   (resume work)    (resume work)    (resume work)

BACK TO INITIAL STATE: Workers running
```

### 4.3 RAG Pipeline Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                  RAG Retrieval Data Flow                        │
└─────────────────────────────────────────────────────────────────┘

USER QUERY: "How do I configure the database?"
                         │
                         ▼
        ┌────────────────────────────────┐
        │ RAGRetriever.retrieve()        │
        └────────────┬───────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ Initialize RAGContext                           │
        │   context = RAGContext.new                      │
        │   context.query = "How do I configure..."       │
        └────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ Step 1: QueryEmbeddingProcessor                 │
        ├─────────────────────────────────────────────────┤
        │ openai_embeddings.embed(query)                  │
        │   ↓                                             │
        │ OpenAI API Call:                                │
        │   POST /v1/embeddings                           │
        │   { model: "text-embedding-3-small",            │
        │     input: "How do I configure..." }            │
        │   ↓                                             │
        │ Returns: FLOAT[1536] vector                     │
        │   [0.123, -0.456, 0.789, ...]                   │
        │   ↓                                             │
        │ context.query_embedding = vector                │
        └────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ Step 2: ConversationSearchProcessor             │
        ├─────────────────────────────────────────────────┤
        │ embedding_store.search_by_type(                 │
        │   type: 'conversation',                         │
        │   query_embedding: context.query_embedding,     │
        │   limit: 3,                                     │
        │   threshold: 0.7,                               │
        │   exclude: [current_conversation_id]            │
        │ )                                               │
        │   ↓                                             │
        │ DuckDB Query (if VSS available):                │
        │   SELECT id, text, embedding,                   │
        │     1 - cosine_distance(embedding, $1) AS sim   │
        │   FROM text_embedding_3_small                   │
        │   WHERE type = 'conversation'                   │
        │     AND id != $2                                │
        │     AND sim >= 0.7                              │
        │   ORDER BY sim DESC                             │
        │   LIMIT 3                                       │
        │   ↓                                             │
        │ Results:                                        │
        │   [                                             │
        │     { id: "conv-123",                           │
        │       text: "Discussed DB config...",           │
        │       similarity: 0.85 },                       │
        │     { id: "conv-456",                           │
        │       text: "Setup instructions...",            │
        │       similarity: 0.78 }                        │
        │   ]                                             │
        │   ↓                                             │
        │ context.conversations = results                 │
        └────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ Step 3: ExchangeSearchProcessor                 │
        ├─────────────────────────────────────────────────┤
        │ For each found conversation (+ current):        │
        │   embedding_store.search_by_type(               │
        │     type: 'exchange',                           │
        │     query_embedding: context.query_embedding,   │
        │     limit: 10,                                  │
        │     threshold: 0.7,                             │
        │     filter_conversations: [conv_ids]            │
        │   )                                             │
        │   ↓                                             │
        │ Similar DuckDB query for exchanges              │
        │   ↓                                             │
        │ Results:                                        │
        │   [                                             │
        │     { id: "exch-789",                           │
        │       conversation_id: "conv-123",              │
        │       text: "User asked about DB path...",      │
        │       similarity: 0.91 },                       │
        │     { id: "exch-012",                           │
        │       conversation_id: "conv-123",              │
        │       text: "Configured connection pool...",    │
        │       similarity: 0.82 }                        │
        │   ]                                             │
        │   ↓                                             │
        │ context.exchanges = results                     │
        └────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ Step 4: ContextFormatterProcessor               │
        ├─────────────────────────────────────────────────┤
        │ Format as markdown:                             │
        │                                                  │
        │ ## Related Conversations                        │
        │                                                  │
        │ - **Conversation from 2024-10-15**              │
        │   Discussed DB config...                        │
        │   (similarity: 0.85)                            │
        │                                                  │
        │ - **Conversation from 2024-10-20**              │
        │   Setup instructions...                         │
        │   (similarity: 0.78)                            │
        │                                                  │
        │ ## Relevant Exchanges                           │
        │                                                  │
        │ ### From Conversation (2024-10-15)              │
        │                                                  │
        │ - User asked about DB path...                   │
        │   (similarity: 0.91)                            │
        │                                                  │
        │ - Configured connection pool...                 │
        │   (similarity: 0.82)                            │
        │   ↓                                             │
        │ context.formatted_context = markdown_text       │
        └────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ Return RAGContext                               │
        │   • query_embedding: FLOAT[1536]                │
        │   • conversations: Array[2]                     │
        │   • exchanges: Array[2]                         │
        │   • formatted_context: String (markdown)        │
        └─────────────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────────────────────────────┐
        │ Used in Context Document for LLM               │
        │                                                 │
        │ # Context for AI Assistant                     │
        │                                                 │
        │ ## Conversation History                        │
        │ [Recent messages...]                           │
        │                                                 │
        │ ## Related Information from Memory (RAG)       │
        │ [formatted_context inserted here]              │
        │                                                 │
        │ ## Available Tools                             │
        │ [Tool definitions...]                          │
        │                                                 │
        │ ## User Query                                  │
        │ How do I configure the database?               │
        └────────────────────────────────────────────────┘
```

---

## Summary

**Nu::Agent** is a well-architected, multi-model AI agent framework with:

1. **Clean Separation of Concerns**: CLI, orchestration, tools, memory, clients, database, and workers are distinct subsystems with clear interfaces.

2. **Extensible Design**: Plugin-style tool registration, multiple LLM provider support, and command pattern for slash commands.

3. **Robust Memory System**: Hierarchical memory (conversations → exchanges → messages) with vector-based RAG retrieval for contextual awareness.

4. **Background Processing**: Asynchronous summarization and embedding generation with pause/resume coordination.

5. **Transaction Safety**: Atomic exchange commits with worker coordination to prevent data corruption.

6. **Multi-Provider Support**: Unified client interface supporting Anthropic, Google, OpenAI, and xAI with provider-specific optimizations.

7. **High Test Coverage**: 98.91% line coverage with 1839+ tests ensuring reliability.

The architecture enables powerful AI agent capabilities while maintaining clean code organization, thread safety, and extensibility for future enhancements.
