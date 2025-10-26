# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

task default: :spec

# Alias tasks
desc "Run tests (alias for spec)"
task test: :spec

desc "Run linter (alias for rubocop)"
task lint: :rubocop

desc "Run the nu-agent application"
task :run do
  sh "clear && ./exe/nu-agent"
end
