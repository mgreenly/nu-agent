# Nu::Agent

[![Specs](https://github.com/mgreenly/nu-agent/actions/workflows/ci.yml/badge.svg)](https://github.com/mgreenly/nu-agent/actions/workflows/ci.yml)
[![Lint](https://github.com/mgreenly/nu-agent/actions/workflows/lint.yml/badge.svg)](https://github.com/mgreenly/nu-agent/actions/workflows/lint.yml)
[![Coverage](https://github.com/mgreenly/nu-agent/actions/workflows/coverage.yml/badge.svg)](https://github.com/mgreenly/nu-agent/actions/workflows/coverage.yml)
[![Dependabot](https://img.shields.io/badge/dependabot-enabled-025E8C?logo=dependabot)](https://github.com/mgreenly/nu-agent/blob/main/.github/dependabot.yml)

A toy AI Agent with multi-model orchestration, rich tooling, and persistent memory.

## Development Status

> **Note**: This project uses trunk-based development. The `master` branch may contain unstable or experimental changes. For stable experimentation, please use the [latest release tag](https://github.com/mgreenly/nu-agent/releases).

**Roadmap**: See [GitHub Issues](https://github.com/mgreenly/nu-agent/issues) for planned features and ongoing work.

## Quick Start

```bash
# Clone and install
git clone https://github.com/yourusername/nu-agent.git
cd nu-agent
bundle install

# Configure API keys
mkdir -p ~/.secrets
echo "your-key" > ~/.secrets/ANTHROPIC_API_KEY
echo "your-key" > ~/.secrets/OPENAI_API_KEY
echo "your-key" > ~/.secrets/GEMINI_API_KEY

# Run
./exe/nu-agent
```

## Dependencies

**DuckDB** (conversation persistence)
```bash
# Debian/Ubuntu
sudo apt-get install libduckdb-dev

# macOS
brew install duckdb
```

If installing manually, configure bundler before `bundle install`:
```bash
bundle config build.duckdb --with-duckdb-dir=$HOME/.local
```

**ripgrep** (code search)
```bash
# Debian/Ubuntu
sudo apt-get install ripgrep

# macOS
brew install ripgrep
```

## Features

Multi-model orchestration (Claude, GPT, Gemini, Grok) with task-specific routing. Rich tooling includes file operations, shell execution, Python REPL, database queries, directory traversal, and semantic grep. Persistent conversation memory stored in DuckDB with message/exchange/session hierarchy. Developer-friendly with debug modes, model switching, and configurable verbosity.
