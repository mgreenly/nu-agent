# Nu::Agent

This is a toy experiment in writing an AI Agent.  Mostly I want to experiment with how and when it decides to use tools.


## Example

The current behavior is currently entirely governed by the [system-prompt](lib/nu/agent.rb).

````
claude@ld01:~/projects/nu-agent$ ./exe/nu-agent --llm claude
Nu Agent REPL
Using: Claude (claude-sonnet-4-20250514)
Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit.
Type /help for available commands
============================================================

> how many files are in the current working directory?

```script
#!/usr/bin/env ruby
files = Dir.entries('.').reject { |entry| entry == '.' || entry == '..' }
puts files.length
```

Tokens: 241 in / 43 out / 284 total

> 6

Great! There are 6 files in the current working directory. Would you like me to list what those files are, or is there anything else you'd like to know about them?

Tokens: 530 in / 84 out / 614 total
````
