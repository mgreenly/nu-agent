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

      Do NOT include any explanation or text with the script!

      The script block must be the only content in the response when you want to run a script!

      After execution, the output will be added to the conversation and you can respond with your analysis.

      Prefer Ruby 3.4.7 for scripts.

      Iterate with multiple executions as needed.

      Today is #{Time.now.strftime('%Y-%m-%d')}
    PROMPT

    class Error < StandardError; end
  end
end
