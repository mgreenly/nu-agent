Nu-Agent Plan: User Documentation

Last Updated: 2025-10-31
Plan Status: Ready to execute

## Overview

Create comprehensive user-facing documentation for nu-agent CLI users, organized as topic-based files that progress from basic installation to advanced features. The plan is designed to be re-runnable: each phase lists specific behaviors and features to document, allowing periodic verification that docs remain accurate as the application evolves.

## Documentation Structure

```
docs/
├── README.md                    (main entry point, overview)
├── getting-started.md          (installation, first run, basics)
├── configuration.md            (settings, options, customization)
├── features.md                 (core features and commands)
├── models.md                   (model selection and configuration)
├── rag-memory.md              (conversational memory and RAG)
├── advanced.md                (advanced usage, workers, admin)
└── troubleshooting.md         (common issues and solutions)
```

## High-Level Motivation

- Provide clear, accessible documentation for end users
- Enable new users to get started quickly (< 10 minutes to first conversation)
- Support progressive learning: basic → intermediate → advanced
- Maintainable structure that can be verified and updated as features change
- Reference documentation for all commands, flags, and configuration options

## Scope (In)

- Installation instructions (all platforms)
- First-run setup and configuration
- Basic REPL usage and commands
- Model selection and switching
- Configuration options and flags
- RAG/conversational memory features
- Background workers and admin commands
- Troubleshooting common issues
- Architecture diagrams where helpful

## Scope (Out)

- Developer/integration documentation (stays in docs/dev/)
- Internal implementation details
- Code contribution guidelines (stays in root)
- Screenshots (text/diagrams only per user preference)

## Implementation Phases

### Phase 1: Getting Started Documentation (2-3 hrs)

**Goal:** Enable new users to install and run nu-agent successfully.

**File:** `docs/getting-started.md`

**Content Sections:**
1. **Introduction**
   - What is nu-agent?
   - Key features overview (1-2 sentences each)
   - System requirements

2. **Installation**
   - Prerequisites (Ruby, DuckDB setup)
   - Installation steps
   - Verification (how to test it works)
   - Link to troubleshooting

3. **First Run**
   - Starting nu-agent
   - Initial setup prompts
   - Your first conversation
   - Basic commands overview

4. **Quick Start Examples**
   - Simple question/answer
   - Multi-turn conversation
   - Using a tool
   - Exiting the application

**Verification Checklist:**
- [ ] Installation instructions work on clean system
- [ ] All prerequisite links are current
- [ ] Setup commands execute without errors
- [ ] Quick start examples run successfully
- [ ] All mentioned commands exist and work as described

**Testing:**
- Manual: Follow installation steps on clean VM/container
- Manual: Execute each example in Quick Start section
- Check: All command names match current CLI

---

### Phase 2: Core Features Documentation (3-4 hrs)

**Goal:** Document all user-facing commands and basic features.

**File:** `docs/features.md`

**Content Sections:**
1. **REPL Interface**
   - Command structure
   - Input/output behavior
   - Streaming responses
   - Conversation history

2. **Commands Reference**
   - Format: `/command [args]` - Description
   - Document each command:
     - `/help` - Show available commands
     - `/clear` - Clear screen
     - `/reset` - Start new conversation
     - `/exit` - Quit application
     - `/info` - Show session information
     - `/models` - List available models
     - `/model` - Switch models
     - `/tools` - Show available tools
     - `/debug` - Toggle debug mode
     - `/verbosity` - Set verbosity level
     - `/redaction` - Toggle redaction mode
     - `/persona` - Manage personas
     - `/rag` - RAG configuration
     - `/worker` - Worker management
     - `/admin` - Admin commands
     - `/backup` - Backup database

3. **Working with Conversations**
   - Session persistence
   - Conversation history
   - Token usage tracking
   - Cost tracking

4. **Tools and Function Calling**
   - What are tools?
   - Available tools (get current list)
   - Tool usage examples
   - Tool output interpretation

**Verification Checklist:**
- [ ] All commands listed are current
- [ ] Command syntax is accurate
- [ ] Each command description matches behavior
- [ ] Examples execute successfully
- [ ] No undocumented commands exist

**Testing:**
- Generate command list: Run `/help` and compare
- Test each command with documented syntax
- Verify examples produce expected output

---

### Phase 3: Configuration Documentation (2-3 hrs)

**Goal:** Document all configuration options and customization.

**File:** `docs/configuration.md`

**Content Sections:**
1. **Configuration Overview**
   - Where configuration is stored
   - Configuration persistence
   - Command-line flags vs runtime commands

2. **Command-Line Options**
   - List all flags from `bin/nuagent`
   - Format: `--flag` - Description - Default value
   - Document:
     - `--debug` - Enable debug output
     - `--reset-model` - Override model selection
     - Any other CLI flags

3. **Runtime Configuration**
   - Settings that persist across sessions
   - Settings that are session-only
   - How to view current config: `/info`

4. **Database Location**
   - Default location: `~/.nuagent/memory.db`
   - Custom location via environment variable
   - Backup and migration

5. **API Keys and Secrets**
   - Required API keys (Anthropic, OpenAI, etc.)
   - Where to store them: `~/.nuagent/secrets/`
   - Format and security considerations

6. **Advanced Configuration**
   - Worker settings
   - RAG parameters
   - Cost tracking settings

**Verification Checklist:**
- [ ] All CLI flags documented and current
- [ ] Default values are accurate
- [ ] Environment variables documented
- [ ] API key setup instructions work
- [ ] Configuration paths exist and are correct

**Testing:**
- Extract flags from source: grep ArgumentParser
- Test each flag: verify behavior matches docs
- Verify default config locations

---

### Phase 4: Models and Providers Documentation (2-3 hrs)

**Goal:** Explain model selection, switching, and provider configuration.

**File:** `docs/models.md`

**Content Sections:**
1. **Understanding Models**
   - What models are available
   - Model roles: orchestrator, summarizer
   - When each model is used
   - Cost implications

2. **Available Models**
   - Anthropic models (Claude variants)
   - OpenAI models (GPT variants)
   - Google models (Gemini variants)
   - X.AI models (Grok variants)
   - Table format: Model | Provider | Use Case | Cost

3. **Model Configuration**
   - Viewing current models: `/models`
   - Switching orchestrator: `/model orchestrator <name>`
   - Switching summarizer: `/model summarizer <name>`
   - Model aliases and shortcuts

4. **Model Selection Best Practices**
   - Speed vs capability tradeoffs
   - Cost optimization strategies
   - Recommended combinations

5. **Provider Setup**
   - API key requirements per provider
   - Rate limits and quotas
   - Provider-specific considerations

**Verification Checklist:**
- [ ] All models listed are currently available
- [ ] Model roles accurately described
- [ ] Switching commands work as documented
- [ ] Cost information is current
- [ ] API key setup for each provider works

**Testing:**
- Generate model list: Run `/models` and compare
- Test model switching: Verify each command
- Check ClientFactory for available models

---

### Phase 5: RAG and Memory Documentation (3-4 hrs)

**Goal:** Explain conversational memory, RAG retrieval, and related features.

**File:** `docs/rag-memory.md`

**Content Sections:**
1. **Conversational Memory Overview**
   - What is conversational memory?
   - How RAG works in nu-agent
   - Automatic vs manual retrieval
   - Benefits and limitations

2. **RAG Configuration**
   - Enabling/disabling RAG: `/rag on|off`
   - Viewing RAG status: `/rag status`
   - Configuration parameters:
     - Conversation limits
     - Token budgets
     - Similarity thresholds
     - Exchange caps
   - Setting parameters: `/rag <param> <value>`

3. **Testing RAG Retrieval**
   - Manual testing: `/rag test <query>`
   - Interpreting results
   - Understanding scores and relevance

4. **Embeddings and Vector Search**
   - What are embeddings?
   - Background embedding generation
   - VSS extension and requirements

5. **Background Workers**
   - What workers do
   - Worker status: `/worker status`
   - Starting/stopping workers
   - Worker configuration
   - Performance metrics

6. **Personas**
   - What are personas?
   - Listing personas: `/persona list`
   - Switching personas: `/persona <name>`
   - Creating custom personas: `/persona create <name>`
   - Editing personas: `/persona edit <name>`

**Verification Checklist:**
- [ ] RAG commands work as documented
- [ ] Configuration parameters are current
- [ ] Test command produces expected output
- [ ] Worker commands accurate
- [ ] Persona commands work correctly

**Testing:**
- Test all `/rag` subcommands
- Verify parameter limits and defaults
- Test `/worker` commands
- Test `/persona` commands
- Check EmbeddingStore for current features

---

### Phase 6: Advanced Features Documentation (2-3 hrs)

**Goal:** Document admin features, debugging, and advanced usage.

**File:** `docs/advanced.md`

**Content Sections:**
1. **Debug Mode**
   - Enabling debug: `/debug on`
   - What debug output shows
   - Verbosity levels: `/verbosity <0-3>`
   - Using debug for troubleshooting

2. **Admin Commands**
   - Viewing failed jobs: `/admin failures`
   - Retrying failed jobs: `/admin retry <id>`
   - Purging data: `/admin purge`
   - Managing backups: `/backup [path]`

3. **Privacy Features**
   - Redaction: `/redaction on|off`
   - What gets redacted
   - Purging conversations
   - Data retention

4. **Performance Optimization**
   - Worker configuration
   - Cache settings
   - Database optimization
   - Cost optimization

5. **Session Management**
   - Session information: `/info`
   - Token usage tracking
   - Cost tracking
   - Resetting sessions: `/reset`

6. **Backup and Recovery**
   - Creating backups: `/backup`
   - Restoring from backup
   - Database migration
   - Data export considerations

**Verification Checklist:**
- [ ] All admin commands documented
- [ ] Debug features work as described
- [ ] Backup process verified
- [ ] Privacy features accurate
- [ ] Performance tips are current

**Testing:**
- Test all `/admin` subcommands
- Verify backup/restore process
- Test redaction functionality
- Validate session tracking

---

### Phase 7: Troubleshooting Documentation (1-2 hrs)

**Goal:** Help users solve common problems.

**File:** `docs/troubleshooting.md`

**Content Sections:**
1. **Installation Issues**
   - DuckDB extension errors
   - Ruby version problems
   - Permission issues
   - Missing dependencies

2. **Runtime Errors**
   - API key errors
   - Connection problems
   - Database locked errors
   - Worker failures

3. **Performance Issues**
   - Slow responses
   - High memory usage
   - Database growth
   - Worker lag

4. **Common Questions**
   - How do I change models?
   - How do I clear history?
   - How do I export conversations?
   - Where are my settings stored?
   - How do I update nu-agent?

5. **Getting Help**
   - How to report bugs
   - Providing useful debug info
   - Community resources
   - GitHub issues link

**Verification Checklist:**
- [ ] All errors mentioned still occur (or remove)
- [ ] Solutions actually work
- [ ] Links are valid
- [ ] Debug commands are current

**Testing:**
- Attempt to reproduce each error
- Test each solution
- Verify all links work

---

### Phase 8: Main Entry Point and Overview (1-2 hrs)

**Goal:** Create welcoming introduction and navigation hub.

**File:** `docs/README.md` (update existing)

**Content Sections:**
1. **Welcome**
   - Brief introduction to nu-agent
   - Key capabilities
   - Who is this for?

2. **Quick Links**
   - New user? → getting-started.md
   - Looking for commands? → features.md
   - Need to configure? → configuration.md
   - Model questions? → models.md
   - Using RAG? → rag-memory.md
   - Advanced user? → advanced.md
   - Having issues? → troubleshooting.md

3. **Documentation Map**
   - Table of contents for all docs
   - Brief description of each file
   - Suggested reading order

4. **Architecture Overview Diagram**
   - Simple diagram showing:
     - User → REPL
     - REPL → LLM (with model options)
     - REPL → Tools
     - Background Workers
     - Database (conversations, embeddings)
   - ASCII art or mermaid diagram

**Verification Checklist:**
- [ ] All links work
- [ ] Descriptions match file content
- [ ] Diagram is accurate
- [ ] Reading order makes sense

**Testing:**
- Click/verify all links
- Review diagram against actual architecture
- Get feedback from new user

---

## Verification and Maintenance Process

### Initial Documentation Pass
1. Write content for each phase/file
2. Follow verification checklist for that file
3. Test all examples and commands
4. Commit completed file

### Periodic Review (quarterly or after major releases)
1. Start at Phase 1
2. Work through each file's verification checklist
3. Test commands and examples
4. Update content where behavior has changed
5. Add sections for new features
6. Remove sections for deprecated features
7. Commit updates with clear messages about what changed

### Quick Verification (for specific changes)
1. Identify which doc files are affected
2. Run verification checklist for those files only
3. Update and commit

### Tools to Assist Verification
- Command list generator: `grep 'def execute' lib/nu/agent/commands/*.rb`
- Model list: Run `/models` command
- Config options: `grep 'ArgumentParser' bin/nuagent`
- Feature check: Run test suite and look for new features

## Success Criteria

- **Completeness**: All user-facing features documented
- **Accuracy**: All examples and commands work as described
- **Accessibility**: New user can get started in < 10 minutes
- **Navigation**: Easy to find information on any topic
- **Maintainability**: Verification checklists make updates straightforward
- **Progressive**: Clear path from beginner to advanced usage

## Notes

- Keep language simple and jargon-free where possible
- Use consistent terminology throughout
- Include working examples for every feature
- Link between related topics liberally
- Maintain verification checklists as features change
- Consider user perspective: "How do I..." not "The system..."
- Each doc file should be independently useful
- Diagrams should be text-based (ASCII art or mermaid) for easy maintenance

## Future Enhancements

- Video tutorials (screencasts)
- Interactive examples
- FAQ section based on actual user questions
- Migration guides for version updates
- Integration examples (if API becomes available)
- Searchable documentation site
