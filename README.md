# Nu::Agent

[![Specs](https://github.com/mgreenly/nu-agent/actions/workflows/ci.yml/badge.svg)](https://github.com/mgreenly/nu-agent/actions/workflows/ci.yml)
[![Lint](https://github.com/mgreenly/nu-agent/actions/workflows/lint.yml/badge.svg)](https://github.com/mgreenly/nu-agent/actions/workflows/lint.yml)
[![Coverage](https://github.com/mgreenly/nu-agent/actions/workflows/coverage.yml/badge.svg)](https://github.com/mgreenly/nu-agent/actions/workflows/coverage.yml)
[![Dependabot](https://img.shields.io/badge/dependabot-enabled-025E8C?logo=dependabot)](https://github.com/mgreenly/nu-agent/blob/main/.github/dependabot.yml)

A toy AI Agent with multi-model orchestration and RAG-powered hierarchical memory using HNSW indexing.

> **Note**: This project uses trunk-based development. The `main` branch may contain unstable or experimental changes. For stable experimentation, please use the [latest release tag](https://github.com/mgreenly/nu-agent/tags).

**Roadmap**: See [GitHub Issues](https://github.com/mgreenly/nu-agent/issues) for planned features and ongoing work.

## Quick Start

```bash
# Clone and setup
git clone https://github.com/yourusername/nu-agent.git
cd nu-agent
bin/setup  # Automatically installs DuckDB and dependencies

# Configure at least one API key
mkdir -p ~/.secrets
echo "your-key" > ~/.secrets/ANTHROPIC_API_KEY
echo "your-key" > ~/.secrets/OPENAI_API_KEY
echo "your-key" > ~/.secrets/GEMINI_API_KEY
echo "your-key" > ~/.secrets/XAI_API_KEY

# Run
./exe/nu-agent
```

## Dependencies

### DuckDB (conversation persistence)

The `bin/setup` script **automatically** handles DuckDB installation:

- **Downloads** pre-built DuckDB v1.4.1 binaries from GitHub
- **Installs locally** to `vendor/duckdb/` (project-specific, not system-wide)
- **Configures bundler** to compile the Ruby gem against the local library
- **Works on Linux and macOS** (x86_64 and ARM64)
- **No sudo required** - perfect for sandboxed environments

If you see errors like "Failed to execute prepared statement" or similar DuckDB errors:

1. **Reinstall DuckDB locally**:
   ```bash
   rm -rf vendor/duckdb
   bin/setup
   ```

2. **Force gem recompilation**:
   ```bash
   gem uninstall duckdb --force
   bundle install

For more detailed troubleshooting, see [docs/setup-duckdb.md](docs/setup-duckdb.md).

### ripgrep (code search)

```bash
# Debian/Ubuntu
sudo apt-get install ripgrep

# macOS
brew install ripgrep
```
