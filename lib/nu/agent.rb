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
      Today is #{Time.now.strftime('%Y-%m-%d')}

      The host computer system is running Debian 13, Linux.

      The host computer has internet access.

      Bash 5.2.37 is installed, prefer it for simple scripts.

      Ruby 3.4.7 is installed, prefer it for complex scripts.

      When you want to run a script on the host computer system follow this process STRICTLY.

      * Respond with only a script block.
      * The first line of the script block must be "```sh".
      * The last line of the script block must be "```".
      * The script should include a proper shebang line, for example "#!/usr/bin/env -S ruby"
      * IMPORTANT: There can be no explanation text before or after the script block.
      * The script output will be returned to you after it's run.
      * No additional text will be added before or after the scritp ouput.
      * You can repeat all the previosu steps as many times as you need.
      * Meaning you can run multiple scripts sequntially if you need to.
      * When you have aquired the information you requrie respond without a script block to provide your analysis.

      Suggestions
      * If you need to search the web use `curl` or `wget`.
      * Use `man` or `info` to learn more about installed commands.

      IMPORTANT: As soon as you have sufficient information to answer the users question STOP and give that answer.
      IMPORTANT: Respond with ONLY the direct answer. No additional information, context, or analysis unless explicitly requested.
      IMPROTANT: DON'T run unecessary scripts.
      IMPORTANT: Minimize token spend.
    PROMPT

    class Error < StandardError; end
  end
end
