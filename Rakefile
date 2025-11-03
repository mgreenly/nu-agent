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
    # Use script to create a pseudo-TTY for terminal-dependent code
    sh "script -e -c 'bundle exec rspec' /dev/null"
  end
end

desc "Run tests with coverage reporting"
task :coverage do
  # Coverage is automatically enabled via spec_helper.rb
  Rake::Task["spec"].invoke
  puts "\n📊 Coverage report generated at coverage/index.html"
  puts "   Open it with: open coverage/index.html (macOS) or xdg-open coverage/index.html (Linux)"
end

# Benchmark tasks
# rubocop:disable Metrics/BlockLength
namespace :benchmark do
  desc "Benchmark test suite performance (usage: rake benchmark:test RUNS=5)"
  task :test do
    require "benchmark"

    runs = (ENV["RUNS"] || "5").to_i
    puts "🔬 Benchmarking test suite performance (#{runs} runs)..."
    puts "=" * 80
    puts

    times = []
    runs.times do |i|
      print "Run #{i + 1}/#{runs}: "
      time = Benchmark.realtime do
        # Run tests silently
        rspec_cmd = "bundle exec rspec --pattern spec/**{,/*/**}/*_spec.rb " \
                    "--format progress > /dev/null 2>&1"
        sh rspec_cmd
      end
      times << time
      puts "#{time.round(2)}s"
    end

    puts
    puts "=" * 80
    puts "📊 Statistics:"
    puts "=" * 80
    mean = times.sum / times.length
    sorted = times.sort
    median_index = sorted.length / 2
    median = if sorted.length.odd?
               sorted[median_index]
             else
               (sorted[median_index - 1] + sorted[median_index]) / 2.0
             end
    variance = times.map { |t| (t - mean)**2 }.sum / times.length
    stddev = Math.sqrt(variance)

    puts "Mean:     #{mean.round(2)}s"
    puts "Median:   #{median.round(2)}s"
    puts "Min:      #{times.min.round(2)}s"
    puts "Max:      #{times.max.round(2)}s"
    puts "Std Dev:  #{stddev.round(2)}s"
    puts "Range:    #{(times.max - times.min).round(2)}s"
    puts
    puts "💡 Baseline (old approach): ~180-240s"
    improvement = ((1 - (mean / 210.0)) * 100).round(0)
    puts "✨ Current performance:     ~#{mean.round(0)}s (#{improvement}% improvement)"
    puts
  end

  desc "Compare file-based vs in-memory database performance"
  task :compare do
    require "benchmark"

    runs = (ENV["RUNS"] || "3").to_i

    puts "🔬 Comparing database configurations (#{runs} runs each)..."
    puts "=" * 80
    puts

    # Benchmark file-based
    puts "📁 File-based database (db/test.db):"
    file_times = []
    runs.times do |i|
      print "  Run #{i + 1}/#{runs}: "
      time = Benchmark.realtime do
        rspec_cmd = "TEST_DB_PATH=db/test.db bundle exec rspec " \
                    "--pattern spec/**{,/*/**}/*_spec.rb --format progress > /dev/null 2>&1"
        sh rspec_cmd
      end
      file_times << time
      puts "#{time.round(2)}s"
    end
    file_mean = file_times.sum / file_times.length

    puts
    puts "💾 In-memory database (:memory:):"
    memory_times = []
    runs.times do |i|
      print "  Run #{i + 1}/#{runs}: "
      time = Benchmark.realtime do
        rspec_cmd = "TEST_DB_PATH=:memory: bundle exec rspec " \
                    "--pattern spec/**{,/*/**}/*_spec.rb --format progress > /dev/null 2>&1"
        sh rspec_cmd
      end
      memory_times << time
      puts "#{time.round(2)}s"
    end
    memory_mean = memory_times.sum / memory_times.length

    puts
    puts "=" * 80
    puts "📊 Comparison:"
    puts "=" * 80
    puts "File-based:  #{file_mean.round(2)}s (mean)"
    puts "In-memory:   #{memory_mean.round(2)}s (mean)"
    improvement = ((file_mean - memory_mean) / file_mean * 100).round(1)
    puts "Difference:  #{(file_mean - memory_mean).round(2)}s (#{improvement}% faster with in-memory)"
    puts
  end
end
# rubocop:enable Metrics/BlockLength

# Parallel test execution tasks
namespace :parallel do
  desc "Run tests in parallel (usage: rake parallel:spec CORES=4)"
  task :spec do
    cores = ENV.fetch("CORES", "4").to_i
    puts "🚀 Running tests in parallel with #{cores} processes..."
    sh "bundle exec parallel_rspec spec/ -n #{cores}"
  end

  desc "Run tests in parallel (shorthand alias)"
  task :test do
    Rake::Task["parallel:spec"].invoke
  end

  desc "Prepare parallel test databases"
  task :prepare do
    cores = ENV.fetch("CORES", "4").to_i
    puts "🗄️  Preparing #{cores} test databases..."
    sh "bundle exec parallel_test -n #{cores} --type rspec -e 'bundle exec rake parallel:setup_db[{{}}]'"
  end

  desc "Setup a single parallel test database (internal use)"
  task :setup_db, [:process_number] do |_t, args|
    # This task is called by parallel_test for each process
    # The database setup is handled by DatabaseHelper in spec_helper.rb
    process_num = args[:process_number]
    puts "Setting up database for process #{process_num}..."
  end
end

desc "Run tests in parallel with default settings (alias for parallel:spec)"
task parallel: "parallel:spec"

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
