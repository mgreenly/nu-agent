# frozen_string_literal: true

require 'duckdb'
require 'fileutils'
require 'forwardable'
require 'json'
require 'open3'
require 'optparse'
require 'readline'
require 'securerandom'

require 'anthropic'
require 'gemini-ai'
require 'openai'

module Nu
  module Agent
    class Error < StandardError; end
  end
end

require_relative "agent/api_key"
require_relative "agent/clients/anthropic"
require_relative "agent/clients/google"
require_relative "agent/clients/openai"
require_relative "agent/clients/openai_embeddings"
require_relative "agent/clients/xai"
require_relative "agent/client_factory"
require_relative "agent/spinner"
require_relative "agent/output_manager"
require_relative "agent/spell_checker"
require_relative "agent/man_indexer"
require_relative "agent/application"
require_relative "agent/formatter"
require_relative "agent/document_builder"
require_relative "agent/history"
require_relative "agent/options"
require_relative "agent/tools/agent_summarizer"
require_relative "agent/tools/man_indexer"
require_relative "agent/tools/database_message"
require_relative "agent/tools/database_query"
require_relative "agent/tools/database_schema"
require_relative "agent/tools/database_tables"
require_relative "agent/tools/dir_create"
require_relative "agent/tools/dir_delete"
require_relative "agent/tools/dir_list"
require_relative "agent/tools/dir_tree"
require_relative "agent/tools/execute_bash"
require_relative "agent/tools/execute_python"
require_relative "agent/tools/file_copy"
require_relative "agent/tools/file_delete"
require_relative "agent/tools/file_edit"
require_relative "agent/tools/file_glob"
require_relative "agent/tools/file_grep"
require_relative "agent/tools/file_move"
require_relative "agent/tools/file_read"
require_relative "agent/tools/file_stat"
require_relative "agent/tools/file_tree"
require_relative "agent/tools/file_write"
require_relative "agent/tools/search_internet"
require_relative "agent/tool_registry"
require_relative "agent/version"
