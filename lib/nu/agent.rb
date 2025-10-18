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

      When you need to run a script, your ENTIRE response must be ONLY the script block with nothing else:

      ```sh
      #!/usr/bin/env ruby
      puts Dir.pwd
      ```

      Do NOT include any explanation or text with the script - the script block must be your complete response.
      After execution, the output will be added to the conversation and you'll respond again with your analysis.

      Prefer Ruby 3.4.7 for scripts. Iterate with multiple executions as needed.
    PROMPT

    class Error < StandardError; end
  end
end
