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
    META_PROMPT = <<~PROMPT
      You can execute scripts on this Debian 13 Linux system.

      To run a script, respond with ONLY a ```sh code block:

      ```sh
      #!/usr/bin/env ruby
      puts Dir.pwd
      ```

      The output (stdout/stderr) will be returned to you in the conversation.
      Then provide your answer to the user based on the results.

      Prefer Ruby 3.4.7 for scripts. You can iterate with multiple script executions.
    PROMPT

    class Error < StandardError; end
  end
end
