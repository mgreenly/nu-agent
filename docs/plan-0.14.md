Nu-Agent v0.14 Plan: Hash-Like Configuration Store

Last Updated: 2025-10-29
Target Version: 0.14.0
Plan Status: Draft for review

Index
- High-level motivation
- Scope (in)
- Scope (out, future enhancements)
- Key technical decisions and hints
- Implementation phases
  - Phase 1: AppConfig class with hash-like interface
  - Phase 2: Command history separation
  - Phase 3: Migration and replacement
  - Phase 4: Documentation and cleanup
- Success criteria
- Risks and mitigations
- Future enhancements
- Notes


High-level motivation
- Replace ConfigStore's explicit getter/setter methods with a more idiomatic, hash-like interface that feels natural to Ruby developers.
- Automatically detect and preserve types (integer, float, string) to eliminate manual type conversions scattered throughout the codebase.
- Separate configuration storage concerns from command history tracking (single responsibility principle).
- Improve developer experience with cleaner, more concise syntax for frequent config access.

Scope (in)
- New AppConfig class with hash-like interface ([], []=, fetch, keys, values, etc.).
- Automatic type detection on retrieval: nil (NULL in DB), booleans (true/false case-insensitive), integers match /^-?\d+$/, floats match /^-?\d+\.\d+$/, everything else is a string.
- Optional read-through caching to reduce database queries for frequently accessed keys.
- Separate CommandHistory class to handle command history storage and retrieval.
- Migration path from ConfigStore to AppConfig throughout the codebase.
- Update all existing config access points (History, WorkerCounter, etc.) to use new interface.
- Comprehensive tests for type detection, edge cases, and hash-like behavior.

Scope (out, future enhancements)
- Complex types (arrays, hashes, nested structures) - keep it simple with scalar values only.
- Write-through caching or distributed cache synchronization.
- Configuration versioning or audit trail.
- Configuration schemas or validation rules.
- Hot-reload or configuration change notifications.

Key technical decisions and hints
- Storage format: Values stored as TEXT in database, with NULL for nil values (no schema changes to appconfig table needed).
- Type detection on read: Apply checks in order to determine type:
  - nil: NULL in database → nil
  - Boolean: "true" or "false" (case-insensitive) → true/false
  - Integer: /^-?\d+$/ → value.to_i
  - Float: /^-?\d+\.\d+$/ → value.to_f
  - String: everything else (including edge cases like "192.168.1.1", "3.14.159", "1.5e10")
- Type conversion on write:
  - nil → NULL in database
  - true → "true", false → "false"
  - Everything else → .to_s
- Hash interface: Implement [], []=, fetch, key?, keys, values, each, to_h to provide familiar Hash-like API.
- Caching strategy: Simple in-memory hash for read-through cache; optional and conservative (cache invalidation on write).
- Single responsibility: CommandHistory handles command_history table exclusively; AppConfig handles appconfig table exclusively.
- SQL safety: Maintain existing parameterized query approach or escape_sql helper; no change to security posture.
- Backward compatibility: Provide deprecated ConfigStore wrapper that delegates to AppConfig for smooth migration if needed.

Implementation phases

Phase 1: AppConfig class with hash-like interface (2-3 hrs)
Goal: Implement core AppConfig class with automatic type detection and hash-like API.
Tasks
- Create lib/nu/agent/app_config.rb
- Implement core methods:
  - initialize(connection, enable_cache: false)
  - [](key) - read with type detection
  - []=(key, value) - write with string conversion
  - fetch(key, default = nil) - read with default fallback
  - key?(key) - check existence
  - keys - return all config keys
  - values - return all config values (parsed)
  - each { |k, v| } - enumerate key-value pairs
  - to_h - return hash representation
  - delete(key) - remove config entry
  - clear - remove all config (with confirmation requirement)
- Implement type detection helper: parse_value(string)
- Implement optional caching: @cache hash with invalidation on writes
- SQL implementation using existing appconfig table structure
Testing
- Unit tests for type detection: nil, booleans (true/false, case variations), integers, floats, strings, edge cases (negatives, decimals, IP addresses)
- Unit tests for hash-like interface: [], []=, fetch, key?, keys, values, each, to_h
- Unit tests for caching: cache hits/misses, invalidation on write
- Test nil handling: NULL in DB returns nil, setting nil stores NULL, missing keys return nil
- Test boolean handling: "true"/"TRUE"/"True" all return true, same for false
- Test edge cases: empty strings, whitespace, special characters in keys/values, "TRUE" vs "True1" (latter is string)

Phase 2: Command history separation (1 hr)
Goal: Extract command history into dedicated class.
Tasks
- Create lib/nu/agent/command_history.rb
- Implement CommandHistory class:
  - initialize(connection)
  - add(command) - validate and insert
  - get(limit: 1000) - retrieve chronologically
  - clear - remove all history (with confirmation)
- Use existing command_history table (no schema changes)
- Maintain existing validation logic (reject nil/empty commands)
Testing
- Unit tests for CommandHistory: add, get, empty command rejection
- Test limit parameter and ordering (chronological)

Phase 3: Migration and replacement (2-3 hrs)
Goal: Replace ConfigStore usage throughout codebase.
Tasks
- Update History class (lib/nu/agent/history.rb):
  - Replace @config_store = ConfigStore.new(connection)
  - Use @app_config = AppConfig.new(connection, enable_cache: true)
  - Use @command_history = CommandHistory.new(connection)
  - Update set_config → @app_config[key] = value
  - Update get_config → @app_config.fetch(key, default)
  - Update command history methods to use @command_history
- Update WorkerCounter (lib/nu/agent/worker_counter.rb):
  - Accept app_config instead of config_store
  - Remove manual .to_i conversions (now automatic)
  - Use @app_config["active_workers"] directly
- Update History instantiation in specs
- Search for any other ConfigStore usage and update
- Optionally: Create deprecated ConfigStore wrapper for gradual migration
Validation
- All existing tests pass with new AppConfig
- WorkerCounter no longer needs .to_i calls
- Config access is cleaner and more concise
Testing
- Run full test suite
- Integration tests verify end-to-end config storage and retrieval
- Verify worker counter increments/decrements work correctly

Phase 4: Documentation and cleanup (1 hr)
Goal: Document new interface and remove old code.
Tasks
- Update relevant docs to reference AppConfig instead of ConfigStore
- Add code examples showing hash-like usage
- Document type detection behavior and supported types
- Mark ConfigStore as deprecated or remove entirely (depending on migration strategy)
- Remove lib/nu/agent/config_store.rb if fully replaced
- Update or remove spec/nu/agent/config_store_spec.rb (or repurpose for AppConfig)
Validation
- Documentation is clear and accurate
- No references to ConfigStore remain (except deprecation warnings if applicable)

Success criteria
- Functional: AppConfig provides hash-like interface with automatic type detection; all existing config operations work identically.
- API improvement: Config access is more concise: config["key"] vs config_store.get_config("key"); types are automatic.
- Test coverage: Comprehensive tests for type detection, hash interface, caching, edge cases.
- Migration complete: All ConfigStore usage replaced; WorkerCounter and other consumers use cleaner syntax.
- Single responsibility: CommandHistory handles command history; AppConfig handles configuration; no mixed concerns.
- No regressions: All existing tests pass; behavior is identical except for improved ergonomics.

Risks and mitigations
- Type detection ambiguity: Leading zeros ("007") become integer 7; "TRUE" becomes boolean true not string; document this behavior clearly with examples.
- Boolean edge cases: Strings like "True1", "trueish", "yes" stay as strings (not booleans); only exact "true"/"false" case-insensitive match.
- nil vs missing key: Both return nil; use key?(key) to distinguish if needed; document this behavior.
- Cache invalidation bugs: Keep caching opt-in and conservative; invalidate entire cache on any write to be safe initially.
- Breaking changes: Provide deprecated ConfigStore wrapper if needed for gradual migration; ensure compatibility layer is tested.
- Migration scope: Search comprehensively for all ConfigStore usage; use grep/tooling to ensure nothing is missed.
- String vs numeric confusion: Document that values like "3.14.159" (two dots) stay as strings; clear type detection rules in tests and docs.

Future enhancements
- Complex types: Support JSON-serialized arrays/hashes for composite configuration values.
- Configuration namespacing: Group related configs with dot notation (e.g., "rag.enabled", "rag.max_results").
- Schema validation: Define expected types and ranges for known config keys; validate on write.
- Change notifications: Pub/sub for configuration changes; allow components to react to config updates.
- Audit trail: Log all config changes with timestamp and optional reason.
- Remote configuration: Sync config from external source or distributed store.
- Environment variable overlay: Allow ENV vars to override database config for deployment flexibility.
- Default values registry: Centralized defaults with documentation for all recognized config keys.
- Type hints: Optional explicit type specification for edge cases where auto-detection is insufficient.

Notes
- AppConfig builds on existing appconfig table schema; no database migrations required for core functionality.
- Type detection is pragmatic: optimized for common config use cases (counters, flags, numeric thresholds, nil for unset).
- Hash-like interface makes configuration feel like a natural Ruby object rather than a database wrapper.
- Caching is optional and conservative; start without it and enable for high-frequency reads if profiling shows benefit.
- Command history separation improves clarity: History delegates to specialized components rather than mixing concerns.
- Consider this a quality-of-life improvement: makes codebase more maintainable and pleasant to work with, no major feature additions.

Example usage comparison:
```ruby
# Before (ConfigStore)
config_store.set_config("debug", "true")
config_store.set_config("max_workers", "8")
config_store.set_config("timeout", "30.5")
value = config_store.get_config("debug")  # returns "true" string
count = config_store.get_config("max_workers").to_i  # manual conversion

# After (AppConfig)
config["debug"] = true
config["max_workers"] = 8
config["timeout"] = 30.5
config["unset_key"] = nil
value = config["debug"]  # returns true (boolean)
count = config["max_workers"]  # returns 8 (integer)
timeout = config["timeout"]  # returns 30.5 (float)
missing = config["unset_key"]  # returns nil
```
