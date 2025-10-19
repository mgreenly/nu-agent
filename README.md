# Nu::Agent

This is a toy experiment in writing an AI Agent.  Mostly just to understand agents better but also specifically becase I want to experiment with how agents decide to use tools.

## Examples

The current behavior is almost entirely governed by the [meta-prompt](lib/nu/agent.rb#L22-L49).

### Example #1

```
$ exe/nu-agent --llm gemini
Nu Agent REPL
Using: Gemini (gemini-2.5-flash)
Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit.
Type /help for available commands
============================================================

> search the web to find the most popular spotify song this week.

The most popular Spotify song globally this week (for the week ending October 17, 2025) is "Starlight Serenade" by Luna Nova.

Tokens: 169 in / 35 out / 204 total

>
```

### Example #2

````
$ exe/nu-agent --llm=gemini

Nu Agent REPL
Using: Gemini (gemini-2.5-flash)
Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit.
Type /help for available commands
============================================================

> how many files are in the current working directory?

There are 10 files in the current working directory.

Tokens: 545 in / 82 out / 627 total

> which is the largest file?

The largest file in the current working directory is `Gemfile.lock`.

Tokens: 1360 in / 245 out / 1605 total

>
````

## Debug

Here's a debug example to see what's going on under the hood.

## Debug #1

```
$ exe/nu-agent --debug --llm gemini
Nu Agent REPL
Using: Gemini (gemini-2.5-flash)
Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit.
Type /help for available commands
============================================================

> how many files are in the current working directory?
[DEBUG] Script detected
[DEBUG] ```sh
[DEBUG] #!/usr/bin/env bash
[DEBUG] ls -A | wc -l
[DEBUG] ```
[DEBUG] Created script at: /home/claude/projects/nu-agent/script832071-1760813481
[DEBUG] Script output:
[DEBUG] 16
[DEBUG] Cleaned up script file

16

Tokens: 787 in / 22 out / 809 total

>
```
## Debug #2

```
$ exe/nu-agent --debug --llm claude
Nu Agent REPL
Using: Claude (claude-sonnet-4-20250514)
Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit.
Type /help for available commands
============================================================

> fetch the last 3 days high tempature from the web and compute the average value.
[DEBUG] Script detected
[DEBUG] ```sh
[DEBUG] #!/bin/bash
[DEBUG] curl -s "https://wttr.in/?format=%t" | head -3 | sed 's/[^0-9.-]//g' | awk '{sum+=$1; count++} END {print sum/count}'
[DEBUG] ```
[DEBUG] Created script at: /home/claude/projects/nu-agent/script832110-1760813559
[DEBUG] Script output:
[DEBUG] 61
[DEBUG] Cleaned up script file
[DEBUG] Script detected
[DEBUG] ```sh
[DEBUG] #!/bin/bash
[DEBUG] # Get weather data for last 3 days with more detailed format
[DEBUG] curl -s "https://wttr.in/?format=j1" | grep -A 3 '"maxtempC"' | grep -o '[0-9]\+' | head -3 | awk '{sum+=$1; count++} END {printf "%.1f\n", sum/count}'
[DEBUG] ```
[DEBUG] Created script at: /home/claude/projects/nu-agent/script832110-1760813563
[DEBUG] Script output:
[DEBUG] 28.3
[DEBUG] Cleaned up script file

The average high temperature over the last 3 days is 28.3°C.

Tokens: 1460 in / 189 out / 1649 total

>
```

## Multi-Stage Prompt Processing Pipeline

Nu-Agent now includes a sophisticated prompt processing pipeline that analyzes user requests for ambiguities before sending them to the LLM. This helps ensure clearer, more accurate responses by resolving ambiguities upfront.

### Features

- **Automatic Ambiguity Detection**: Uses the LLM to identify ambiguous terms or unclear directions in your requests
- **Interactive Clarification**: Prompts you to clarify specific ambiguous elements before processing
- **Smart Context Enhancement**: Appends your clarifications to the original request for better understanding
- **Configurable**: Control the maximum number of ambiguities and other settings
- **Toggle On/Off**: Enable or disable the pipeline with the `/pipeline` command

### Example Usage

```
> Make it better
🔍 Analyzing request for ambiguities...

📝 Found 2 ambiguous term(s) that need clarification.
I need some clarification to better understand your request:

1. Regarding 'it':
   What specifically does 'it' refer to?
   > the code performance

2. Regarding 'better':
   Better in what way - performance, readability, or something else?
   > faster execution time

✅ Clarifications added. Processing enhanced request...
```

The final prompt sent to the LLM includes your clarifications:
```
Make it better

Context and clarifications:
- it: the code performance
- better: faster execution time
```

### Commands

- `/pipeline` - Toggle the prompt processing pipeline on/off
- `/help` - Shows pipeline status along with other commands

### Configuration

The pipeline can be configured when initializing the application:

```ruby
config = {
  max_ambiguities: 3,        # Maximum number of ambiguities to detect
  debug: false,              # Enable debug output
  ask_for_clarification: true # Whether to prompt for clarifications
}
```

## TODO

Future experiments I could do.

  * Have the system specific metadata info by dynamically generated.
  * Don't save the `meta-prompt` in the history.  Instead always wrap the most immediate request with it to maintain it's immediacy.
  * add a `/llm NAME` command so you can switch LLMs before any prompt.
  * add a `/model NAME` command so you can switch MODEL before any prompt.
  * lots of error/debug imrprovements
  * Add more pipeline stages: intent classification, prompt rewriting, safety checks
  * Make pipeline configuration available via command-line options
  * Add persistence for clarifications to reuse in similar contexts

## NOTES

### Original Clarification Challenge

It's hard to get the model to ask for clarification but this worked. The solution was to implement a dedicated prompt processing pipeline that uses the LLM itself to detect ambiguities before processing the main request.

### How It Was Solved

Instead of trying to get the model to ask for clarification during normal conversation, we implemented a **multi-stage pipeline**:

1. **Ambiguity Detection Stage**: Before processing any user request, we send it to the LLM with a specific prompt asking it to identify ambiguous terms
2. **Interactive Clarification**: For each ambiguity detected, we prompt the user for clarification
3. **Context Enhancement**: We append the clarifications to the original request before sending it to the LLM for processing

This approach ensures consistent clarification behavior without depending on the model's willingness to ask questions during normal operation.

### Implementation Details

The pipeline architecture allows for easy extension with additional stages:
- **Current**: Ambiguity Resolution Stage
- **Future**: Intent Classification, Prompt Rewriting, Safety Checks, etc.

Each stage operates independently and can be enabled/disabled or configured as needed.
