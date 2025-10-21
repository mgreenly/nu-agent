# frozen_string_literal: true

require 'forwardable'
require 'json'
require 'open3'
require 'optparse'

require 'anthropic'
require 'gemini-ai'

require_relative "agent/api_key"
require_relative "agent/anthropic_client"
require_relative "agent/application_v2"
require_relative "agent/formatter"
require_relative "agent/google_client"
require_relative "agent/history"
require_relative "agent/options"
require_relative "agent/tool"
require_relative "agent/bash_tool"
require_relative "agent/tool_registry"
require_relative "agent/version"

module Nu
  module Agent
    class Error < StandardError; end
  end
end
