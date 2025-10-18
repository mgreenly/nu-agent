# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Run the nu-agent application"
task :run do
  sh "clear && ./exe/nu-agent"
end
