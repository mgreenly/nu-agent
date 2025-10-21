# Nu::Agent

This is a learning experiment to understand how AI agents work, particularly focusing on how agents decide when and how to use tools. The goal is to build a simple but complete agent architecture from first principles.

## Architecture

Nu::Agent implements a database-backed conversational agent with tool calling support. Conversations are stored in DuckDB, allowing full history tracking and replay. The architecture abstracts LLM providers (currently supporting Anthropic's Claude and Google's Gemini) behind a common interface that handles message formatting and tool calling protocols. Tools are defined with JSON schemas and can be invoked by the LLM during conversation. The agent uses a simple orchestrator that manages the conversation loop: user input → LLM response → tool execution (if needed) → LLM response with results → repeat. 

## Example

```
$ exe/nu-agent --debug --llm google
Nu Agent v2 REPL
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
