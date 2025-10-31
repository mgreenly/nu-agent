# frozen_string_literal: true

# SimpleCov must be loaded before application code
require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  add_filter "/vendor/"

  # Only enforce minimum coverage when COVERAGE_ENFORCE is set
  if ENV["COVERAGE_ENFORCE"] == "true"
    # Goal: gradually increase to 100%
    minimum_coverage line: 98.57, branch: 90.13
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
