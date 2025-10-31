# frozen_string_literal: true

# SimpleCov must be loaded before application code
require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  add_filter "/vendor/"

  # Only enforce minimum coverage when COVERAGE_ENFORCE is set
  if ENV["COVERAGE_ENFORCE"] == "true"
    # Current baseline coverage (as of 2025-10-31 after v0.12 rebase)
    # Goal: gradually increase to 100%
    # Note: Set to 98.15% / 90.00% after rebasing v0.12 onto main (actual: 98.17% line / 90.02% branch)
    # Combined coverage from main (persona refactoring) + v0.12 (RAG improvements, metrics, privacy)
    # Maintaining 0.02% margin above required threshold
    minimum_coverage line: 98.15, branch: 90.00
  end
end

require "nu/agent"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
