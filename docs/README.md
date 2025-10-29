Nu-Agent Documentation Index

Purpose
- Provide a single entry point to the project documentation
- Establish consistent naming and grouping conventions for docs

Table of Contents
- Plans
  - plan-0.11.md — Conversational Memory (RAG) delivery plan
  - plan-0.12.md — UX, Observability, and Maintainability plan
- Design
  - design-rag-overview.md — RAG concepts and overview
  - design-rag-implementation.md — RAG implementation details and processors
  - architecture-analysis.md — Architecture layers and analysis
  - design-threaded-subprocess.md — Threaded subprocess design
  - design-overview.md — General design overview
- Setup
  - setup-duckdb.md — DuckDB setup, VSS extension, and troubleshooting
- Standards
  - naming-conventions.md — Project naming conventions and patterns (consolidated)

Naming conventions (consolidated)
- Use plan-*, design-*, setup-*, standards-*, and tools-* prefixes to group by purpose
- Prefer kebab-case filenames
- Keep domain grouping when helpful (e.g., design-rag-*)
- For dated snapshots, suffix with YYYY-MM (e.g., architecture-analysis-2025-10.md)
- File moves should also update intra-doc references in the repository

Quick links
- RAG overview: docs/design-rag-overview.md
- RAG impl: docs/design-rag-implementation.md
- DuckDB setup: docs/setup-duckdb.md
- Current plan: docs/plan-0.11.md

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
