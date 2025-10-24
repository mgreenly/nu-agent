# Nu-Agent Classes

## Core Application Classes

- **Nu::Agent::Error** - Standard error class for all agent-related exceptions
- **Nu::Agent::Application** - Main REPL orchestrator managing conversation lifecycle, threading, and command routing
- **Nu::Agent::Options** - Command-line argument parser for model selection and debug mode configuration
- **Nu::Agent::History** - DuckDB-backed persistence layer for conversations, messages, and configuration state
- **Nu::Agent::Formatter** - Terminal output formatter with debug modes, token tracking, and message display
- **Nu::Agent::OutputManager** - Thread-safe output coordinator synchronizing spinner and message display
- **Nu::Agent::Spinner** - Animated terminal spinner with elapsed time tracking for long-running operations
- **Nu::Agent::SpellChecker** - Automatic user input spell correction using gemini-2.5-flash LLM
- **Nu::Agent::ApiKey** - Secure API key wrapper preventing accidental logging or inspection
- **Nu::Agent::ClientFactory** - Factory pattern implementation for creating provider-specific LLM clients
- **Nu::Agent::ToolRegistry** - Tool registration system with provider-specific schema formatting

## LLM Client Classes

- **Nu::Agent::Clients::Anthropic** - Claude API integration with message formatting and cost calculation
- **Nu::Agent::Clients::Google** - Gemini API integration with multi-modal content support
- **Nu::Agent::Clients::OpenAI** - OpenAI GPT API integration with function calling support
- **Nu::Agent::Clients::XAI** - X.AI Grok API client inheriting OpenAI-compatible interface

## Tool Classes

### Database Tools
- **Nu::Agent::Tools::DatabaseMessage** - Retrieves historical messages by ID from conversation database
- **Nu::Agent::Tools::DatabaseQuery** - Executes read-only SQL queries against conversation history
- **Nu::Agent::Tools::DatabaseSchema** - Inspects table schemas and column definitions
- **Nu::Agent::Tools::DatabaseTables** - Lists all available database tables

### File System Tools
- **Nu::Agent::Tools::FileRead** - Reads file contents with line number formatting and range selection
- **Nu::Agent::Tools::FileWrite** - Creates or overwrites files with specified content
- **Nu::Agent::Tools::FileEdit** - Performs exact string replacement edits within files
- **Nu::Agent::Tools::FileCopy** - Copies files between locations with overwrite protection
- **Nu::Agent::Tools::FileMove** - Moves or renames files atomically
- **Nu::Agent::Tools::FileDelete** - Removes files with safety checks
- **Nu::Agent::Tools::FileStat** - Retrieves file metadata including size, permissions, and timestamps
- **Nu::Agent::Tools::FileGlob** - Pattern-based file discovery using glob syntax
- **Nu::Agent::Tools::FileGrep** - Content-based file search with regex pattern matching
- **Nu::Agent::Tools::FileTree** - Generates hierarchical file structure visualization

### Directory Tools
- **Nu::Agent::Tools::DirCreate** - Creates directories recursively with proper permissions
- **Nu::Agent::Tools::DirDelete** - Removes directories with safety checks and recursive option
- **Nu::Agent::Tools::DirList** - Lists directory contents with detailed file information
- **Nu::Agent::Tools::DirTree** - Generates hierarchical directory structure visualization

### Execution Tools
- **Nu::Agent::Tools::ExecuteBash** - Executes bash commands in sandboxed temporary scripts
- **Nu::Agent::Tools::ExecutePython** - Executes Python code with stdout/stderr capture

### Meta Tools
- **Nu::Agent::Tools::AgentSummarizer** - Background conversation summarization for context compression
