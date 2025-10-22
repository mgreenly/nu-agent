# Nu::Agent

This is a personal learning experiment to better understand how AI agents work, in paticular how they handle context and tool usage.


## Example

This agent currently uses a DuckDB database to store a permananet memory.  It also has an idea of a sessions and only includes that in the context of messages.  Even with that it heavily redacts messages that are replayed in the context.  The below example demonstrates it using the ruby tool to create an execute a script.  This script then will only exist as a redacted message with an id in future context to the mdoel.  So when I ask it to fetch the first few lines of the script it actually has to use the `read_redacted_message` tool to fetch the unredacted text.

The idea of course being that most large scripts are not relevant for most later queries and don't really need to stay in context.

This is an area I want to experiement with.  An always on agent with a single permanent history that uses lots of sub-agents to groom that memory behind the scenes and selectively build the most relevant context it can for each new message to the model.


```
$ exe/nu-agent --debug --model gpt-5-nano
Nu Agent REPL
Using: OpenAI (gpt-5-nano-2025-08-07)
Type your prompts below. Press Ctrl-C, Ctrl-D, or /exit to quit.
Type /help for available commands
============================================================


> Create a ruby script that implements qsort then use it to sort 10 random integers.  Only show me the results.


[Tool Call] execute_ruby
  script: #!/usr/bin/env ruby

def qsort(arr)
  return arr if arr.length <= 1
  pivot = arr.sample
  left = []
  middle = []
  right = []
  arr.each do |x|
    if x < pivot
      left << x
    elsif x == pivot
      middle << x
    else
      right << x
    end
  end
  qsort(left) + middle + qsort(right)
end

arr = Array.new(10) { rand(100) }
sorted = qsort(arr)
puts sorted.join(' ')

Session tokens: 813 in / 926 out / 1739 (0.4% of 400000)
Session spend: $0.000411

[Tool Result] execute_ruby
  stdout:
    11 39 39 46 68 69 79 81 85 89
  stderr:
  exit_code: 0
  success: true

> 11 39 39 46 68 69 79 81 85 89

Session tokens: 1825 in / 1146 out / 2971 (0.7% of 400000)
Session spend: $0.000550


> Can you show me the first 10 lines of that script?


[Tool Call] read_redacted_message
  message_id: 661

Session tokens: 2780 in / 1684 out / 4464 (1.1% of 400000)
Session spend: $0.000813

[Tool Result] read_redacted_message
  message_id: 661
  role: assistant
  timestamp: 2025-10-21 22:13:08 -0500
  tool_calls: [{"tool_name" => "execute_ruby", "arguments" => {"script" => "#!/usr/bin/env ruby\n\ndef qsort(arr)\n  return arr if arr.length <= 1\n  pivot = arr.sample\n  left = []\n  middle = []\n  right = []\n  arr.each do |x|\n    if x < pivot\n      left << x\n    elsif x == pivot\n      middle << x\n    else\n      right << x\n    end\n  end\n  qsort(left) + middle + qsort(right)\nend\n\narr = Array.new(10) { rand(100) }\nsorted = qsort(arr)\nputs sorted.join(' ')\n"}}]

> #!/usr/bin/env ruby
>
> def qsort(arr)
>   return arr if arr.length <= 1
>   pivot = arr.sample
>   left = []
>   middle = []
>   right = []
>   arr.each do |x|
>     if x < pivot

Session tokens: 3948 in / 2512 out / 6460 (1.6% of 400000)
Session spend: $0.001202


> /exit


Goodbye!
```
