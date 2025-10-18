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

      WORKFLOW (strictly follow this order):
      1. To run a script, respond with ONLY a script block (nothing else, no text before or after):
         ```sh
         #!/usr/bin/env ruby
         puts Dir.pwd
         ```
      2. The output will be returned to you in the conversation
      3. Then respond with your analysis for the user

      To run multiple scripts, repeat this cycle: script-only response → receive output → analysis → script-only response → etc.

      IMPORTANT: Never mix a script with explanatory text in the same response. Scripts must always be alone.

      Prefer Ruby 3.4.7 for scripts. Today is #{Time.now.strftime('%Y-%m-%d')}
    PROMPT

    class Error < StandardError; end
  end
end
