# frozen_string_literal: true

require_relative "lib/nu/agent/version"

# rubocop:disable Metrics/BlockLength
Gem::Specification.new do |spec|
  spec.name = "nu-agent"
  spec.version = Nu::Agent::VERSION
  spec.authors = ["Michael Greenly"]
  spec.email = ["mgreenly@gmail.com"]

  spec.summary = "AI coding agent with multi-model orchestration and tool execution"
  spec.description = <<~DESC
    Nu::Agent is an AI coding agent that orchestrates multiple LLM providers
    (Claude, GPT, Gemini, Grok) with a rich tool library for code execution,
    file operations, database queries, and more. Features persistent conversation
    history in DuckDB with planned RAG capabilities.
  DESC

  spec.homepage = "https://github.com/mgreenly/nu-agent"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/mgreenly/nu-agent",
    "bug_tracker_uri" => "https://github.com/mgreenly/nu-agent/issues",
    "changelog_uri" => "https://github.com/mgreenly/nu-agent/releases",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "exe/*"]
  spec.bindir = "exe"
  spec.executables = ["nu-agent"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "duckdb", "~> 1.3"
  spec.add_dependency "gemini-ai", "~> 4.0"
  spec.add_dependency "ruby-anthropic", "~> 0.4.2"
  spec.add_dependency "ruby-openai", ">= 7", "< 9"
end
# rubocop:enable Metrics/BlockLength
