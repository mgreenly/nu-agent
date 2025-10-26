# frozen_string_literal: true

require_relative "lib/nu/agent/version"

Gem::Specification.new do |spec|
  spec.name = "nu-agent"
  spec.version = Nu::Agent::VERSION
  spec.authors = ["Michael Greenly"]
  spec.email = ["mgreenly@gmail.com"]
  spec.summary = "AI agent framework with multi-provider LLM support"
  spec.homepage = "https://github.com/mgreenly/nu-agent"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files = Dir["lib/**/*", "exe/*"]
  spec.bindir = "exe"
  spec.executables = ["nu-agent"]
  spec.require_paths = ["lib"]

  spec.add_dependency "curses", "~> 1.4"
  spec.add_dependency "duckdb", "~> 1.1"
  spec.add_dependency "gemini-ai", "~> 4.0"
  spec.add_dependency "ruby-anthropic", "~> 0.4.2"
  spec.add_dependency "ruby-openai", "~> 7.0"
  spec.metadata["rubygems_mfa_required"] = "true"
end
