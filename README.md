# Nu::Agent

A toy AI Personal/Coding Agent.

## Features

- **Learning Friendly** - Debug modes, model switching, configurable verbosity, and conversation reset.
- **Multi-Model Orchestration** - Uses Claude, GPT, Gemini, and Grok models. Routes specific tasks to specialized models.
- **Rich Tool Library** - File operations, shell execution, Python REPL, database queries, directory traversal, and semantic grep.
- **Google Search API** - Faster internet searhces vs using curl.
- **Persistent Memory** - Conversations stored in DuckDB with message/exchange/session hierarchy.
- **Retrieval Augmented Generation (RAG)** - Vector embeddings for conversation history and document stores. (wip)
- **Background Intelligence** - Automatic conversation summarization with configurable models. (wip)
- **Model Context Protocol (MCP)** - Support for external tool providers. (coming)
- **Language Server Protocol (LSP)** - Direct integration with language servers for enhanced code generation context. (coming)

## Setup

### Prerequisites

**DuckDB Installation Required**

The `duckdb` Ruby gem requires DuckDB to be installed with headers available. You have two options:

**Option 1: System Package Manager** (Recommended)
```bash
# Debian/Ubuntu
sudo apt-get install libduckdb-dev

# macOS with Homebrew
brew install duckdb
```

**Option 2: Manual Installation**

Download pre-built binaries from [DuckDB releases](https://github.com/duckdb/duckdb/releases) and extract to a local directory (e.g., `~/.local`):

```bash
# Example structure:
~/.local/lib/libduckdb.so       # Library file
~/.local/include/duckdb.h       # Header file
```

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/nu-agent.git
   cd nu-agent
   ```

2. **Configure Bundler for DuckDB**

   If you installed DuckDB to a custom location (Option 2), configure bundler:
   ```bash
   bundle config build.duckdb --with-duckdb-dir=/path/to/duckdb

   # Example for ~/.local installation:
   bundle config build.duckdb --with-duckdb-dir=$HOME/.local
   ```

3. **Install dependencies**
   ```bash
   bundle install
   ```

4. **Configure API keys**

   Create API key files in `~/.secrets/`:
   ```bash
   mkdir -p ~/.secrets
   echo "your-api-key-here" > ~/.secrets/ANTHROPIC_API_KEY
   echo "your-api-key-here" > ~/.secrets/OPENAI_API_KEY
   echo "your-api-key-here" > ~/.secrets/GEMINI_API_KEY
   # Optional: X.AI uses OpenAI-compatible format
   ```

5. **Run the agent**
   ```bash
   ./exe/nu-agent

   # Or with options:
   ./exe/nu-agent --model gpt-5-nano-2025-08-07
   ./exe/nu-agent --debug
   ```

### Troubleshooting

**"cannot load such file -- duckdb" error:**
- Verify DuckDB is installed and headers are accessible
- Check your `.bundle/config` has the correct `--with-duckdb-dir` path
- Try re-running `bundle install` after configuring bundler

**"API key not found" error:**
- Ensure API key files exist in `~/.secrets/` directory
- Verify file permissions allow reading
- Check there are no extra spaces or newlines in the key files
