# Nu::Agent

This is a toy experiment in writing an AI Agent.  Mostly just to understand agents better but also specifically becase I want to experiment with how agents decide to use tools.


## Example

The current behavior is almost entirely governed by the [system-prompt](lib/nu/agent.rb#L22-L46).

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

So in the above example when it was sent the prompt:

> how many files are in the current working directory?

it responded with this prompt.

````
```script
#!/usr/bin/env ruby
puts Dir.glob('*').select { |f| File.file?(f) }.count
```
````

The agent ran the provided script and the output was `10`.

Then the agent appended `10` to the conversation to generate the next prompt.

And the LLM responded with:

> There are 10 files in the current working directory.
