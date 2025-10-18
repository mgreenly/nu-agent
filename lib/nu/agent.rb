# frozen_string_literal: true

# Stdlib
require 'forwardable'
require 'optparse'

# External gems
require 'anthropic'
require 'gemini-ai'

# Internal files
require_relative "agent/api_key"
require_relative "agent/application"
require_relative "agent/claude_client"
require_relative "agent/gemini_client"
require_relative "agent/options"
require_relative "agent/token_tracker"
require_relative "agent/version"

module Nu
  module Agent
    class Error < StandardError; end
    # Your code goes here...
  end
end
