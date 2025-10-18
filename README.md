# Nu::Agent

This is a toy experiment in writing an AI Agent.  Mostly just to understand agents better but also specifically becase I waqnt to experiment with how agents decide to use tools.


## Example

The current behavior is almost entirely governed by the [system-prompt](lib/nu/agent.rb#L22-L46).

````
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
