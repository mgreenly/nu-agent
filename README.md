# Nu::Agent

This is a learning experiment to understand how AI agents work.  In paticular I'm focusing my experiments on having a permanant and complete multi-session memory that the agent uses to build a relevant context from for each query. Also providing tools so that the LLM can explore that memory as it sees fit.  Also just the general idea of using many sub-agents to provide additional metadata for every query.

## Example

```
$ exe/nu-agent --debug --model gemini
Nu Agent REPL
Using: Google (gemini-2.0-flash-exp)
Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit.
Type /help for available commands
============================================================


> How many files are in the current working directory?


[Tool Call] execute_bash
  command: ls -l | wc -l

Tokens: 93 in / 11 out / 104 total

[Tool Result] execute_bash
  stdout:
    13
  stderr:
  exit_code: 0
  success: true

There are 13 files in the current working directory.

Tokens: 118 in / 13 out / 131 total


> /exit


Goodbye!
```

## Architecture

Nu::Agent implements a database-backed conversational agent with tool calling support. Conversations are stored in DuckDB, allowing full history tracking and replay. The architecture abstracts LLM providers (currently supporting Anthropic's Claude, Google's Gemini, and OpenAI) behind a common interface that handles message formatting and tool calling protocols. Tools are defined with JSON schemas and can be invoked by the LLM during conversation. The agent uses a simple orchestrator that manages the conversation loop: user input → LLM response → tool execution (if needed) → LLM response with results → repeat.

## Usage

Run the agent with a specific model:

```bash
# Use Claude Sonnet 4.5 (default)
exe/nu-agent

# Use a specific model by alias
exe/nu-agent --model haiku
exe/nu-agent --model opus
exe/nu-agent --model gemini
exe/nu-agent --model gpt-4o

# Use a specific model by full ID
exe/nu-agent --model claude-sonnet-4-5-20250929
exe/nu-agent --model gemini-2.0-flash-exp
```

### Available Models

**Anthropic Claude:**
- `sonnet` or `claude-sonnet-4-5` → claude-sonnet-4-5-20250929
- `haiku` or `claude-haiku-4-5` → claude-haiku-4-5-20251001
- `opus` or `claude-opus-4-1` → claude-opus-4-1-20250805

**Google Gemini:**
- `gemini` or `gemini-2.0-flash` → gemini-2.0-flash-exp

**OpenAI:**
- `gpt-5`, `gpt-4o`, `gpt-4o-mini`, etc. 

