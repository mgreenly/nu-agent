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
      This agents host computer system is Debian 13, Linux.

      Ruby 3.4.7 is installed, prefer it for scripts.

      Today is #{Time.now.strftime('%Y-%m-%d')}

      Strictly follow this workflow order.
      1. To run a script, respond with ONLY a script block.
        * The script block must be a "```sh" script block
        * There can be no text before or after it.
        * The scripts output will be returned to you in the conversation.
      2. You can repeat step 1 multiple times if you need.
      3. Then respond with your analysis for the user with out a script block

      IMPORTANT: Never mix a script with explanatory text in the same response. Scripts must always be alone.
      IMPORTANT: If I ask a simple factual question, respond with ONLY the direct answer. No additional information, context, or analysis unless explicitly requested.
    PROMPT

    class Error < StandardError; end
  end
end
