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

# Coverage tasks
namespace :coverage do
  desc "Run tests with coverage enforcement (fails if coverage drops below baseline)"
  task :enforce do
    ENV["COVERAGE_ENFORCE"] = "true"
    Rake::Task["spec"].invoke
  end
end

desc "Run tests with coverage reporting"
task :coverage do
  # Coverage is automatically enabled via spec_helper.rb
  Rake::Task["spec"].invoke
  puts "\n📊 Coverage report generated at coverage/index.html"
  puts "   Open it with: open coverage/index.html (macOS) or xdg-open coverage/index.html (Linux)"
end

# Migration tasks
namespace :migration do
  desc "Generate a new migration file (usage: rake migration:generate NAME=migration_name)"
  task :generate do
    require_relative "lib/nu/agent/migration_generator"

    name = ENV.fetch("NAME", nil)
    if name.nil? || name.strip.empty?
      puts "Error: Migration name is required"
      puts "Usage: rake migration:generate NAME=create_users_table"
      exit 1
    end

    generator = Nu::Agent::MigrationGenerator.new
    file_path = generator.generate(name)

    puts "Created migration: #{file_path}"
    puts "\nNext steps:"
    puts "  1. Edit the migration file to add your SQL"
    puts "  2. Run the application to apply pending migrations"
  rescue ArgumentError => e
    puts "Error: #{e.message}"
    exit 1
  end
end
