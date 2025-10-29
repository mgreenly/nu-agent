# Claude Code Tools

This document lists the tools available to Claude Code for assisting with software engineering tasks.

## Available Tools (17 total)

### File Operations
1. **Read** - Read file contents (supports text, images, PDFs, Jupyter notebooks)
2. **Edit** - Make precise string replacements in files
3. **Write** - Create new files
4. **NotebookEdit** - Edit Jupyter notebook cells

### Search & Discovery
5. **Glob** - Find files using glob patterns (e.g., `**/*.rb`, `src/**/*.ts`)
6. **Grep** - Search file contents with regex patterns

### Execution & Automation
7. **Bash** - Execute shell commands in a persistent session
8. **BashOutput** - Monitor output from background shell processes
9. **KillShell** - Terminate background shell processes

### Web & External Resources
10. **WebFetch** - Fetch and analyze web content
11. **WebSearch** - Search the web for current information

### Task Management & Planning
12. **TodoWrite** - Create and manage structured task lists
13. **ExitPlanMode** - Exit planning mode when ready to code

### Agent & Workflow
14. **Task** - Launch specialized agents (Explore, Plan, general-purpose, etc.)
15. **Skill** - Execute specialized skills
16. **SlashCommand** - Execute custom slash commands

### User Interaction
17. **AskUserQuestion** - Ask clarifying questions with multiple-choice options

## Tool Usage Principles

- **Parallel execution**: Multiple independent tools can be called simultaneously
- **Specialized tools first**: Use dedicated tools instead of bash commands when possible
- **Task tool for exploration**: Use Task tool with Explore agent for codebase discovery
- **Read before Edit/Write**: Always read files before modifying them
