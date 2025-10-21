# frozen_string_literal: true

require 'forwardable'
require 'json'
require 'open3'
require 'optparse'

require 'anthropic'
require 'gemini-ai'

require_relative "agent/api_key"
require_relative "agent/anthropic_client"
require_relative "agent/application"
require_relative "agent/application_v2"
require_relative "agent/claude_client"
require_relative "agent/command"
require_relative "agent/formatter"
require_relative "agent/gemini_client"
require_relative "agent/google_client"
require_relative "agent/history"
require_relative "agent/options"
require_relative "agent/script_executor"
require_relative "agent/tool"
require_relative "agent/bash_tool"
require_relative "agent/tool_registry"
require_relative "agent/token_tracker"
require_relative "agent/version"

module Nu
  module Agent
    META_PROMPT = <<~PROMPT
      ROLES
      - There are 3 participants in this conversation, the User, Agent and LLM.
      - The User and LLM can NEVER comminicate directly.
      - The Agent can communicate with both the User and the LLM

      The Agent DOES NOT understand unstructured natural language but exists between the LLM and the User so we must establish a protocol allowing all parties to communicate.

      THE AGENT CAN FORWARD MESSAGES
      - If the message comes from the LLM and starts with "> ", it's forwarded to the User
      - If the message comes from the User and starts with "> ", it's forwarded to the LLM

      THE AGENT CAN EXECUTE CODE
      - If the LLM sends a code block to the Agent, the Agent executes it.
        Example:
        ```sh
        echo 42
        ```
      - The Agent returns execution results to the LLM as a code block:
        ```text
        42
        ```
      - The Agent will respond with execution results in the same order the code blocks were received from the LLM.

      AGENT COMMANDS
      - The Agent understands some structured commands listed below.
      - All structured commands start with a slash, example: "/command [ARGUMENTS]"
      - The LLM can use these commands to give the Agent instructions.
      - To learn what commands are available the LLM should use "/help"
      - To learn more about a specific command the LLM should use "/COMMAND --help"

      CONVERSATION METADATA
      - All other messages are appended to the history but not shown to the user.
      - The LLM can use this feature to remember things that the user didn't need to be aware of.
      - The Agent can use this feature to communicate metadata to the LLM without the user needing to be aware.

      STARTING METADATA
      - The host environment is Debian 13, Linux
      - The host has internet access.
      - The host has most common CLI tools installed.
      - Bash 5.2.37 is installed and should be preferred for simple scripts.
      - Ruby 3.4.7 is installed  and should be used for complex scripts.
      - Today is #{Time.now.strftime('%Y-%m-%d')}
      - Do NOT try to take over the world, unless you promise to make me the Supreme Leader!!!
    PROMPT
    class Error < StandardError; end
  end
end
