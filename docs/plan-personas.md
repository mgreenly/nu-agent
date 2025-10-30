Nu-Agent: Switchable Agent Personas Plan

Last Updated: 2025-10-30
GitHub Issue: #12
Plan Status: Phase 3 Complete - Ready for Phase 4

## Progress Summary

**Phase 1: COMPLETE** ✅
- Created migration 006_create_personas_table.rb
- Created PersonaManager class with full CRUD operations
- All tests passing (98.91% line coverage)

**Phase 2: COMPLETE** ✅
- Implemented PersonaCommand with list, show, delete, and switch functionality
- Editor integration placeholders for create/edit (Phase 4)
- All tests passing

**Phase 3: COMPLETE** ✅
- Added {{DATE}} replacement in all LLM clients (Anthropic, OpenAI, Google)
- Integrated personas with Application class
- Active persona's system_prompt is loaded and passed to LLM calls
- All tests passing (1894 examples, 0 failures, 98.88% line coverage, 90.73% branch coverage)

**Phase 4: TODO**
- Editor integration for /persona create and /persona edit

**Phase 5: TODO**
- End-to-end testing and documentation updates

Index
- Background and current state
- High-level motivation
- Scope (in)
- Scope (out, future enhancements)
- Key technical decisions
- Database schema
- Default personas
- Implementation phases
  - Phase 1: Database schema and PersonaManager
  - Phase 2: Implement /persona command
  - Phase 3: Integrate personas with LLM clients
  - Phase 4: Editor integration for create/edit
  - Phase 5: Testing and refinement
- Success criteria
- Future enhancements
- Notes

Background and current state
============================

Current System Prompt Architecture
-----------------------------------
The system currently uses hardcoded system prompts defined in each LLM client:

1. **Anthropic client** (lib/nu/agent/clients/anthropic.rb:11-28):
   - Has SYSTEM_PROMPT constant with agent instructions
   - Includes date, formatting rules, tool usage guidelines, pseudonyms
   - Passed to send_message(system_prompt: SYSTEM_PROMPT) with default

2. **OpenAI client** (lib/nu/agent/clients/openai.rb):
   - Accepts system_prompt parameter in send_message()
   - Formats as { role: "system", content: system_prompt }
   - Prepends to message list

3. **Google client** (lib/nu/agent/clients/google.rb):
   - Accepts system_prompt parameter
   - Formats as user message with system instructions
   - Google Gemini doesn't have native system role

Current Flow:
```
Application -> Client.send_message(messages:, system_prompt: DEFAULT, tools:)
            -> Format for provider -> Send to API
```

Key Insight: The system_prompt parameter already exists and flows through all clients.
We just need to make it configurable instead of hardcoded.

Database Structure
------------------
Current database file: ./memory.db (DuckDB)
Existing tables: conversations, exchanges, messages, embeddings, appconfig, schema_migrations

The appconfig table stores key-value configuration (single row):
- debug (boolean)
- model_name (string)
- embedding_service (string)
- Various verbosity flags (integers)

High-level motivation
=====================
- Users need different agent behaviors for different tasks (coding vs writing vs research)
- Current hardcoded system prompt doesn't adapt to different use cases
- Enable users to create, switch between, and customize agent personas
- Each persona defines complete agent behavior through its system prompt
- Personas persist across sessions and survive restarts

User Experience Goals:
- Simple switching: `/persona developer` to change behavior immediately
- Easy discovery: `/persona` to see what's available
- Customization: `/persona create` and `/persona edit` for tailored behaviors
- Professional defaults: Ship with useful personas users can customize

Scope (in)
==========
- Create `personas` database table to store persona definitions
- Implement PersonaManager class to handle CRUD operations
- Add `/persona` command with full subcommand suite:
  - `/persona` or `/persona list` - Show all personas, highlight active one
  - `/persona <name>` - Switch to named persona (applies to new conversations)
  - `/persona create <name>` - Create new persona (opens editor)
  - `/persona edit <name>` - Edit existing persona (opens editor)
  - `/persona delete <name>` - Delete persona (with confirmation)
  - `/persona show <name>` - Display persona's system prompt
- Track active persona in appconfig table
- Integrate persona system with existing LLM clients (use selected persona's prompt)
- Ship with 3-5 default personas (developer, writer, researcher, etc.)
- Editor integration for creating/editing personas (respects $EDITOR)
- Migration to create personas table and populate defaults
- Full test coverage for PersonaManager and PersonaCommand

Scope (out, future enhancements)
================================
- Per-conversation persona overrides (conversation-specific behavior)
- Persona import/export for sharing (JSON/YAML format)
- Persona templates or scaffolding (wizards to help create personas)
- Persona inheritance (base persona + modifications)
- Persona variables/interpolation (e.g., {{date}}, {{project_name}})
- Persona effectiveness tracking (which personas get better results)
- Community persona repository or sharing
- Persona versioning or history
- A/B testing different personas
- Automatic persona suggestion based on conversation context

Key technical decisions
=======================

Database Design
---------------
- Create new `personas` table (not store in appconfig)
- Schema: id, name, system_prompt, created_at, updated_at
- Unique constraint on name (case-insensitive comparison)
- Store active_persona_id in appconfig table (NULL = use default)
- Default persona has name "default" (required, cannot be deleted)

Persona Manager
---------------
- Create lib/nu/agent/persona_manager.rb
- Handles all CRUD operations for personas
- Methods: list(), get(name), create(name, prompt), update(name, prompt), delete(name), set_active(name)
- Returns structured data (hashes/arrays) for commands to format
- Validates persona names (alphanumeric, dashes, underscores only)
- Prevents deletion of default persona and active persona

Command Integration
-------------------
- Create lib/nu/agent/commands/persona_command.rb
- Parse subcommands: list, show, create, edit, delete, switch
- Use PersonaManager for all operations
- Format output for user display
- Handle errors gracefully with clear messages

Editor Integration
------------------
- Reuse existing editor workflow (similar to /edit command if exists)
- Write prompt to temp file, open in $EDITOR, read back on save
- Default to ENV['EDITOR'] || 'vi'
- For create: start with template/example prompt
- For edit: start with existing prompt
- Validate non-empty prompt on save

Client Integration
------------------
- Application loads active persona on startup
- Pass persona's system_prompt to client.send_message()
- No changes needed to client classes (they already accept system_prompt)
- When persona switches, new prompt applies to next conversation

Default Personas
----------------
Ship with 5 default personas (immutable examples users can copy):
1. **default** - Current system prompt (balanced, general-purpose)
2. **developer** - Concise, technical, code-focused
3. **writer** - Creative, exploratory, verbose, storytelling
4. **researcher** - Thorough, cites sources, structured analysis
5. **teacher** - Patient, explains concepts, uses analogies (ELI5 style)

Users can edit these defaults or create new ones.

Naming Conventions
------------------
- Persona names: lowercase, alphanumeric, dashes, underscores
- No spaces, no special characters (keep it shell-friendly)
- Max length: 50 characters
- Reserved names: none (even "system" or "admin" are allowed)

Database schema
===============

Migration: 00X_create_personas_table.sql
-----------------------------------------
```sql
-- Create personas table
CREATE TABLE personas (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  system_prompt TEXT NOT NULL,
  is_default BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add active_persona_id to appconfig
ALTER TABLE appconfig ADD COLUMN active_persona_id INTEGER REFERENCES personas(id);

-- Insert default personas (see "Default Personas" section below)
```

Note: Use DuckDB syntax (similar to SQLite). The migration framework is already in place.

Default personas
================

These should be inserted during migration:

1. default (is_default=TRUE)
----------------------------
```
Today is {{DATE}}.

Format all responses in raw text, do not use markdown.

If you can determine the answer to a question on your own, use your tools to find it instead of asking.

Use execute_bash for shell commands and execute_python for Python scripts.

These are your only tools to execute processes on the host.

You can use your database tools to access memories from before the current conversation.

You can use your tools to write scripts and you have access to the internet.

# Pseudonyms
- "project" can mean "the current directory"
```

2. developer
------------
```
You are a focused software development assistant. Be concise and technical.

Today is {{DATE}}.

Guidelines:
- Prioritize code quality, security, and maintainability
- Use tools to search codebases before asking for clarification
- Format responses in plain text (no markdown)
- Be direct and efficient with explanations
- Focus on practical solutions over theory
- Use execute_bash and execute_python to verify your suggestions

You have access to database tools for conversation history and the internet for research.

Pseudonyms: "project" = current directory
```

3. writer
---------
```
You are a creative writing assistant. Be exploratory, verbose, and imaginative.

Today is {{DATE}}.

Your role:
- Help brainstorm ideas and explore possibilities
- Provide detailed, nuanced feedback on writing
- Suggest alternatives and expansions
- Think about narrative, character, and style
- Be encouraging and generative

You can use tools to research topics, but focus on creative development.
Format responses in plain text.

Pseudonyms: "project" = current directory
```

4. researcher
-------------
```
You are a thorough research assistant. Be structured, cite sources, and provide comprehensive analysis.

Today is {{DATE}}.

Your approach:
- Search for information using available tools before answering
- Cite sources when providing information
- Structure responses with clear sections and summaries
- Distinguish between facts, interpretations, and opinions
- Highlight gaps in knowledge or conflicting information
- Use database tools to reference past research
- Format in plain text with clear organization

Pseudonyms: "project" = current directory
```

5. teacher
----------
```
You are a patient teaching assistant. Explain concepts clearly using analogies and examples.

Today is {{DATE}}.

Teaching style:
- Break down complex topics into simple steps
- Use analogies and real-world examples
- Check understanding before moving forward
- Encourage questions and curiosity
- Adapt explanations to the learner's level
- Use tools to demonstrate concepts when helpful
- Format in plain text for clarity

Pseudonyms: "project" = current directory
```

Note: {{DATE}} should be replaced with actual date at runtime by the client.

Implementation phases
=====================

Phase 1: Database schema and PersonaManager (2 hrs)
----------------------------------------------------
Goal: Create database infrastructure and core persona management logic.

Tasks:
- Create migration file: lib/nu/agent/migrations/00X_create_personas_table.rb
  - Create personas table with schema above
  - Add active_persona_id column to appconfig
  - Insert 5 default personas (use SQL heredocs)
  - Set "default" persona as active
- Create lib/nu/agent/persona_manager.rb
  - Initialize with database connection
  - Implement list() -> Array of persona hashes
  - Implement get(name) -> persona hash or nil
  - Implement create(name:, system_prompt:) -> persona hash
  - Implement update(name:, system_prompt:) -> persona hash
  - Implement delete(name:) -> boolean (with validations)
  - Implement get_active() -> persona hash
  - Implement set_active(name:) -> persona hash
  - Validate persona names (regex: /^[a-z0-9_-]+$/, max 50 chars)
  - Prevent deletion of default persona
  - Prevent deletion of active persona
  - Handle duplicate name errors gracefully
- Update lib/nu/agent/configuration_loader.rb
  - Add active_persona_id to Configuration struct
  - Load active_persona_id from appconfig
- Update lib/nu/agent/application.rb
  - Add @persona_manager instance variable
  - Load active persona on initialization
  - Expose persona_manager via attr_reader

Testing:
- Run migration on fresh database, verify tables created
- Verify 5 default personas exist with correct names
- Test PersonaManager.list() returns all personas
- Test PersonaManager.get("default") returns default persona
- Test PersonaManager.create with valid name succeeds
- Test PersonaManager.create with invalid name fails (spaces, uppercase, etc.)
- Test PersonaManager.create with duplicate name fails
- Test PersonaManager.update changes system_prompt
- Test PersonaManager.delete removes persona
- Test PersonaManager.delete("default") fails with error
- Test PersonaManager.delete(active_persona) fails with error
- Test PersonaManager.get_active() returns correct persona
- Test PersonaManager.set_active(name) updates appconfig

Phase 2: Implement /persona command (2 hrs)
--------------------------------------------
Goal: Create command to list, show, switch, and delete personas.

Tasks:
- Create lib/nu/agent/commands/persona_command.rb
  - Inherit from BaseCommand
  - Parse input into subcommand and arguments
  - Subcommands: [none/list], show, create, edit, delete, [name for switch]
  - Handle `/persona` or `/persona list`:
    - Display all personas in organized format
    - Highlight active persona with marker (e.g., "* default")
    - Show persona names only, not full prompts
  - Handle `/persona <name>` (switch):
    - Validate persona exists
    - Set as active via persona_manager.set_active(name)
    - Display confirmation: "Switched to persona: <name>"
    - Note: "This will apply to your next conversation"
  - Handle `/persona show <name>`:
    - Display persona name and full system_prompt
    - Format nicely with clear boundaries
  - Handle `/persona delete <name>`:
    - Confirm deletion (or just delete with warning)
    - Call persona_manager.delete(name)
    - Display success or error message
    - Prevent deletion of default/active (PersonaManager handles this)
  - Handle `/persona create <name>` and `/persona edit <name>`:
    - Display message: "Editor integration coming in Phase 4"
    - Return :continue for now (implement in Phase 4)
- Register command in lib/nu/agent/application.rb
  - Add to command registry/dispatcher

Testing:
- Test `/persona` lists all personas
- Test `/persona list` same as `/persona`
- Test `/persona default` switches to default persona
- Test `/persona nonexistent` shows helpful error
- Test `/persona show default` displays full prompt
- Test `/persona show nonexistent` shows error
- Test `/persona delete custom-persona` succeeds
- Test `/persona delete default` fails with error
- Test `/persona delete <active>` fails with error
- Test command parsing handles extra spaces correctly
- Test command with no arguments shows help/list

Phase 3: Integrate personas with LLM clients (1.5 hrs)
-------------------------------------------------------
Goal: Use active persona's system prompt when sending messages to LLM.

Tasks:
- Update lib/nu/agent/clients/anthropic.rb:
  - Keep SYSTEM_PROMPT constant as fallback
  - Update send_message() default: system_prompt: SYSTEM_PROMPT
  - No other changes needed (already accepts system_prompt parameter)
  - Add dynamic date injection: replace {{DATE}} with Time.now.strftime('%Y-%m-%d')
- Update lib/nu/agent/clients/openai.rb:
  - Similar to Anthropic (already accepts system_prompt)
  - Add {{DATE}} replacement
- Update lib/nu/agent/clients/google.rb:
  - Similar to Anthropic (already accepts system_prompt)
  - Add {{DATE}} replacement
- Update lib/nu/agent/application.rb:
  - Load active persona in initialize()
  - Store @active_persona_prompt
  - When calling client.send_message(), pass system_prompt: @active_persona_prompt
  - When persona switches, update @active_persona_prompt for next conversation
- Find where send_message is called (likely in message handling loop)
  - Update to use active persona's system_prompt instead of default

Testing:
- Start agent, verify default persona is active
- Send message, verify LLM receives default persona's system prompt
- Switch to "developer" persona
- Send message in NEW conversation, verify developer prompt is used
- Check that {{DATE}} is replaced with actual date in all clients
- Test with all three clients (Anthropic, OpenAI, Google)
- Verify old conversations still reference their original persona

Phase 4: Editor integration for create/edit (2 hrs)
----------------------------------------------------
Goal: Allow users to create and edit personas using $EDITOR.

Tasks:
- Create lib/nu/agent/persona_editor.rb (or add to PersonaCommand)
  - Method: edit_in_editor(initial_content: "", persona_name: nil)
  - Create temporary file in /tmp/nu-agent-persona-<name>-<timestamp>.txt
  - Write initial_content to temp file
  - Open in editor: system("#{ENV['EDITOR'] || 'vi'} #{temp_file.path}")
  - Read back content after editor closes
  - Validate content (non-empty, reasonable length)
  - Return edited content or nil if cancelled/empty
  - Clean up temp file
- Update lib/nu/agent/commands/persona_command.rb:
  - Handle `/persona create <name>`:
    - Validate name format (use PersonaManager validation)
    - Check name doesn't already exist
    - Prepare template prompt (use default persona as example)
    - Call edit_in_editor(initial_content: template, persona_name: name)
    - If content returned, create persona via persona_manager.create()
    - Display success message with persona name
  - Handle `/persona edit <name>`:
    - Validate persona exists
    - Load current system_prompt via persona_manager.get(name)
    - Call edit_in_editor(initial_content: current_prompt, persona_name: name)
    - If content returned and changed, update via persona_manager.update()
    - Display success message
    - If no changes, display "No changes made"
- Handle editor errors gracefully:
  - If $EDITOR not found, display helpful message
  - If editor returns non-zero, warn user
  - If temp file can't be created, show error

Testing:
- Test `/persona create test-persona` opens editor with template
- Edit and save, verify persona is created
- Test `/persona edit test-persona` opens editor with existing prompt
- Modify and save, verify persona is updated
- Test cancelling edit (exit editor without saving)
- Test with empty content (should abort creation/edit)
- Test with missing $EDITOR (should use 'vi' as default)
- Test temp file cleanup after editor closes
- Test creating persona with invalid name (spaces, etc.) shows error before opening editor
- Test editing non-existent persona shows error

Phase 5: Testing and refinement (1 hr)
---------------------------------------
Goal: End-to-end testing and documentation updates.

Tasks:
- Manual testing scenarios:
  - Fresh database: verify 5 default personas exist
  - List personas: `/persona`
  - Switch personas: `/persona developer`, send message, verify behavior
  - Create custom persona: `/persona create my-assistant`
  - Edit custom persona: `/persona edit my-assistant`
  - Show persona: `/persona show developer`
  - Delete custom persona: `/persona delete my-assistant`
  - Try to delete default: verify error
  - Try to delete active persona: verify error
- Update help text:
  - Add `/persona` section to help_command.rb
  - Include all subcommands with examples
  - Explain persona behavior (applies to new conversations)
- Documentation:
  - Update README (if exists) with persona feature
  - Document default personas and their purposes
- Code review:
  - Ensure all edge cases handled
  - Verify error messages are helpful
  - Check for SQL injection (use parameterized queries)
  - Validate test coverage

Testing:
- Run full test suite: rspec spec/
- Verify no regressions in existing functionality
- Check test coverage for PersonaManager and PersonaCommand
- Test with different LLM clients (Anthropic, OpenAI, Google)
- Test persona switching across sessions (restart agent)
- Test migration on existing database (backward compatibility)

Success criteria
================
- Database: personas table exists with 5 default personas
- Command: `/persona` lists all personas with active marked
- Command: `/persona <name>` switches active persona
- Command: `/persona create <name>` opens editor and creates persona
- Command: `/persona edit <name>` opens editor and updates persona
- Command: `/persona delete <name>` removes persona (with validations)
- Command: `/persona show <name>` displays full system prompt
- Integration: Active persona's prompt is used for LLM calls
- Persistence: Active persona survives agent restart
- Protection: Cannot delete default or active persona
- Validation: Persona names follow rules (lowercase, no spaces, etc.)
- Defaults: 5 useful personas ship with the system
- Tests: Full coverage for PersonaManager and PersonaCommand
- Help: `/help` includes persona documentation

Future enhancements
===================
- **Persona import/export**: Share personas as JSON/YAML files
- **Persona templates**: Guided creation with common patterns
- **Persona variables**: {{date}}, {{username}}, {{project_name}} interpolation
- **Per-conversation override**: Temporarily use different persona for one conversation
- **Persona inheritance**: Create persona based on another with modifications
- **Community personas**: Repository of user-contributed personas
- **Effectiveness tracking**: Measure which personas produce better results
- **Persona suggestions**: Auto-suggest persona based on conversation topic
- **Persona versioning**: Track changes to personas over time
- **Persona preview**: Test persona without switching active
- **Bulk operations**: Import multiple personas at once
- **Search/filter**: Find personas by keywords in their prompts

Notes
=====
- The system_prompt parameter already flows through all clients, so integration is straightforward
- Personas apply to NEW conversations, not existing ones (conversations remember their initial persona)
- Default personas use {{DATE}} placeholder that clients replace with actual date
- Editor integration reuses standard shell editor pattern ($EDITOR variable)
- PersonaManager handles all business logic; PersonaCommand handles UI/formatting
- Cannot delete "default" persona or currently active persona (safety)
- Persona names must be shell-friendly (lowercase, no spaces) for potential CLI expansion
- Migration should handle existing databases gracefully (add column, insert defaults)
- Test coverage should include edge cases: invalid names, duplicate names, missing personas
- Consider adding `/persona copy <old> <new>` in future for easy customization

Example usage
=============
```
# List available personas
> /persona
Available personas (* = active):
  * default         - General-purpose assistant
    developer       - Focused software development
    writer          - Creative writing assistant
    researcher      - Thorough research and analysis
    teacher         - Patient teaching and explanations

# Switch to developer persona
> /persona developer
Switched to persona: developer
Note: This will apply to your next conversation.

# Show what a persona says
> /persona show developer
Persona: developer
System Prompt:
----------------------------------------
You are a focused software development assistant. Be concise and technical.

Today is {{DATE}}.

Guidelines:
- Prioritize code quality, security, and maintainability
[... rest of prompt ...]
----------------------------------------

# Create a custom persona
> /persona create code-reviewer
Opening editor to create persona 'code-reviewer'...
[Editor opens with template]
Persona 'code-reviewer' created successfully.

# Edit a persona
> /persona edit code-reviewer
Opening editor to edit persona 'code-reviewer'...
[Editor opens with current prompt]
Persona 'code-reviewer' updated successfully.

# Delete a custom persona
> /persona delete code-reviewer
Persona 'code-reviewer' deleted successfully.

# Try to delete default (fails)
> /persona delete default
Error: Cannot delete the default persona.

# Try to delete active persona (fails)
> /persona delete developer
Error: Cannot delete the currently active persona. Switch to another persona first.
```

Files to create
===============
- lib/nu/agent/migrations/00X_create_personas_table.rb - Database migration
- lib/nu/agent/persona_manager.rb - Core persona CRUD logic
- lib/nu/agent/commands/persona_command.rb - User-facing command
- lib/nu/agent/persona_editor.rb - Editor integration (optional, could be in command)
- spec/nu/agent/persona_manager_spec.rb - PersonaManager tests
- spec/nu/agent/commands/persona_command_spec.rb - PersonaCommand tests

Files to modify
===============
- lib/nu/agent/configuration_loader.rb - Load active_persona_id
- lib/nu/agent/application.rb - Initialize PersonaManager, register command, use active persona
- lib/nu/agent/commands/help_command.rb - Add persona documentation
- lib/nu/agent/clients/anthropic.rb - Add {{DATE}} replacement (minor)
- lib/nu/agent/clients/openai.rb - Add {{DATE}} replacement (minor)
- lib/nu/agent/clients/google.rb - Add {{DATE}} replacement (minor)

Key code locations
==================
Current system prompt: lib/nu/agent/clients/anthropic.rb:11-28 (SYSTEM_PROMPT constant)
Client send_message: lib/nu/agent/clients/anthropic.rb:58 (accepts system_prompt parameter)
Configuration loading: lib/nu/agent/configuration_loader.rb
Migration framework: lib/nu/agent/schema_manager.rb and lib/nu/agent/migration_manager.rb
Command base class: lib/nu/agent/commands/base_command.rb
Database connection: Available via app.history.db (DuckDB)

Getting started
===============
1. Read through this plan completely
2. Create the migration file first (Phase 1)
3. Run migration to verify table creation
4. Implement PersonaManager with tests (Phase 1)
5. Implement PersonaCommand with basic subcommands (Phase 2)
6. Integrate with Application to use active persona (Phase 3)
7. Add editor integration (Phase 4)
8. End-to-end testing and documentation (Phase 5)

Each phase builds on the previous one. Test thoroughly before moving to next phase.
