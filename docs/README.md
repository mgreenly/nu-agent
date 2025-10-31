Nu-Agent Documentation Index

Purpose
- Provide a single entry point to the project documentation
- Establish consistent naming and grouping conventions for docs

Table of Contents
- Overview
  - [Project README](../README.md) — Project overview and quick start
- Plans
  - [dev/plan-0.11.md](dev/plan-0.11.md) — Conversational Memory (RAG) delivery plan
  - [dev/plan-0.12.md](dev/plan-0.12.md) — UX, Observability, and Maintainability plan
- Design
  - [dev/design-rag-overview.md](dev/design-rag-overview.md) — RAG concepts and overview
  - [dev/design-rag-implementation.md](dev/design-rag-implementation.md) — RAG implementation details and processors
  - [dev/architecture-analysis.md](dev/architecture-analysis.md) — Architecture layers and analysis
  - [dev/design-threaded-subprocess.md](dev/design-threaded-subprocess.md) — Threaded subprocess design
  - [dev/design-overview.md](dev/design-overview.md) — General design overview
- Setup
  - [dev/setup-duckdb.md](dev/setup-duckdb.md) — DuckDB setup, VSS extension, and troubleshooting
- Standards
  - Naming conventions (see below)

Naming conventions (consolidated)
- Use plan-*, design-*, setup-*, standards-*, and tools-* prefixes to group by purpose
- Prefer kebab-case filenames
- Keep domain grouping when helpful (e.g., design-rag-*)
- For dated snapshots, suffix with YYYY-MM (e.g., architecture-analysis-2025-10.md)
- File moves should also update intra-doc references in the repository

Quick links
- RAG overview: dev/design-rag-overview.md
- RAG impl: dev/design-rag-implementation.md
- DuckDB setup: dev/setup-duckdb.md
- Current plan: dev/plan-0.11.md

Standards: Naming conventions
- Class names
  - Orchestrator/Manager/Builder/Processor roles are explicit in names
  - Repository for domain entities; Store for infrastructure/cache
  - Clients use provider name only (Anthropic, Google, OpenAI, XAI)
  - Commands use [Action]Command and inherit from BaseCommand
- Methods
  - create_ for top-level entity creation; add_ for children to collections
  - get_ for single entities; plural noun for collections (messages, conversations)
  - update_ for modifications; complete_ for workflow transitions
  - execute for orchestrators/commands/tools; process for processors
  - build for data structures; format_* for pure transforms; display_* for console output
- Variables
  - Full words in public APIs; abbreviations only in local scope when obvious
  - Booleans: predicate? methods; attributes as adjectives or _enabled suffix
  - Collections: simple plurals only; no _list/_items suffixes
- Constants and modules
  - SCREAMING_SNAKE_CASE and frozen
  - Acronyms: Uppercase in classes (ConsoleIO), lowercase in variables (api_key)
  - Directory structure mirrors module hierarchy

When to update this index
- Add new docs under the appropriate prefix and update the TOC
- If you rename or move a file, update all intra-doc references
- Keep this file concise and focused on navigation and conventions
