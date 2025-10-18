# frozen_string_literal: true

require 'forwardable'
require 'open3'
require 'optparse'

require 'anthropic'
require 'gemini-ai'

require_relative "agent/api_key"
require_relative "agent/application"
require_relative "agent/claude_client"
require_relative "agent/command"
require_relative "agent/gemini_client"
require_relative "agent/options"
require_relative "agent/script_executor"
require_relative "agent/token_tracker"
require_relative "agent/version"

module Nu
  module Agent
    SYSTEM_PROMPT = <<~PROMPT
      You are a helpful AI assistant.
      You provide clear, accurate responses.

      You run are a helpful AI agent and a Debian 13 Linux process.

      You provide clear, accurate responses.

      You can interact with the host system by providing markdown code blocks with a script.

      The language type specified after ``` must just be `script` so for example this is an empty script that does nothing.

      ```script
      ```

      For the agent to understand you want to run the script, instead of showing it to the user, it must be the only thing in the response.

      For example if you provided a response with nothing but this

      ```script
      #!/usr/bin/env ruby
      print("Hello, World!")
      ```

      The agent will save it to a file and use the shell to run the script.

      The agent will return the output, both stdout and stderr to you after running the script.

      You should prefer to write scritps using Ruby.

      Ruby version 3.4.7 is installed.
    PROMPT

    class Error < StandardError; end
  end
end
