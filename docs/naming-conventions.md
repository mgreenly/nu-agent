Project Naming Conventions

Guiding principles
- Short but not abbreviated in public APIs
- Ruby idioms first: predicates use ?, keyword args dominant, clarity over cleverness
- Semantic clarity and consistency over time

Class names
- Orchestrator/Manager/Builder/Processor suffixes for roles
- Repository for domain entities; Store for infrastructure/cache
- Clients named by provider only (Anthropic, Google, OpenAI, XAI)
- Commands as [Action]Command, inherit from BaseCommand

Methods
- create_ for top-level creation; add_ for children to collections
- get_ for single entities; simple plural for collections
- update_ for modifications; complete_ for workflow transitions
- execute for orchestrators/commands/tools; process for processors
- build returns data; format_* transforms data; display_* produces output

Variables
- Full words in public APIs; abbreviations only in local scope (attrs, args, pos)
- Booleans: predicate? methods; attributes use adjectives or _enabled suffix
- Collections use simple plurals only; no _list/_items suffixes

Constants and modules
- SCREAMING_SNAKE_CASE and frozen
- Acronyms uppercase in classes (ConsoleIO), lowercase in variables (api_key)
- Module hierarchy mirrors file structure

Checklist
- Class names follow role patterns
- Methods use correct verbs and patterns
- No abbreviations in public APIs
- Boolean methods end with ?; no is_/has_/can_ prefixes
- Collections named as simple plurals
- Constants frozen and properly cased
- File and module names aligned
