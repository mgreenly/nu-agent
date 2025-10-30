# frozen_string_literal: true

# SimpleCov must be loaded before application code
require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  add_filter "/vendor/"

  # Only enforce minimum coverage when COVERAGE_ENFORCE is set
  if ENV["COVERAGE_ENFORCE"] == "true"
    # Current baseline coverage (as of 2025-10-30)
    # Goal: gradually increase to 100%
    # Note: Set to 98.3% to account for CI rounding differences (actual: 98.33%)
    # Branch coverage slightly lower due to new :command output type implementation
    minimum_coverage line: 98.3, branch: 89.9
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
