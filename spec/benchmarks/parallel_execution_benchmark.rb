# frozen_string_literal: true

require "spec_helper"
require "benchmark"
require "fileutils"

# This benchmark suite measures the performance improvements from parallel tool execution
#
# Usage:
#   bundle exec rspec spec/benchmarks/parallel_execution_benchmark.rb --format documentation
#
# Note: This is not part of the regular test suite. Run it separately to collect performance data.
RSpec.describe "Parallel Execution Performance Benchmarks", :benchmark do
  let(:tool_registry) { Nu::Agent::ToolRegistry.new }
  let(:history) { instance_double(Nu::Agent::History) }
  let(:parallel_executor) { Nu::Agent::ParallelExecutor.new(tool_registry: tool_registry, history: history) }
  let(:dependency_analyzer) { Nu::Agent::DependencyAnalyzer.new(tool_registry: tool_registry) }
  let(:test_dir) { "/tmp/parallel_benchmark_test" }

  before(:all) do
    # Create test directory and files
    @test_dir = "/tmp/parallel_benchmark_test"
    FileUtils.mkdir_p(@test_dir)

    # Create 20 test files with some content to simulate realistic file operations
    20.times do |i|
      File.write("#{@test_dir}/file_#{i}.txt", "Test content for file #{i}\n" * 100)
    end
  end

  after(:all) do
    # Clean up test files
    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
  end

  describe "5 independent FileRead operations" do
    let(:tool_calls) do
      5.times.map do |i|
        {
          "id" => "call_#{i}",
          "name" => "file_read",
          "arguments" => { "file" => "#{test_dir}/file_#{i}.txt" }
        }
      end
    end

    it "executes faster than sequential would" do
      # Warm up
      parallel_executor.execute_batch(tool_calls)

      # Measure parallel execution (actual implementation)
      parallel_time = Benchmark.realtime do
        5.times { parallel_executor.execute_batch(tool_calls) }
      end
      parallel_avg = parallel_time / 5.0

      # Measure sequential execution (simulated by batching individually)
      sequential_time = Benchmark.realtime do
        5.times do
          tool_calls.each { |tc| parallel_executor.execute_batch([tc]) }
        end
      end
      sequential_avg = sequential_time / 5.0

      speedup = sequential_avg / parallel_avg

      puts "\n  📊 5 FileRead Operations:"
      puts "     Parallel avg:   #{(parallel_avg * 1000).round(2)}ms"
      puts "     Sequential avg: #{(sequential_avg * 1000).round(2)}ms"
      puts "     Speedup:        #{speedup.round(2)}x"

      # We expect some speedup, though not necessarily 5x due to overhead
      expect(speedup).to be >= 1.0
    end

    it "produces correct results" do
      results = parallel_executor.execute_batch(tool_calls)

      expect(results.length).to eq(5)
      results.each_with_index do |result, i|
        expect(result[:result][:error]).to be_nil
        expect(result[:result][:content]).to include("Test content for file #{i}")
      end
    end
  end

  describe "10 independent FileRead operations" do
    let(:tool_calls) do
      10.times.map do |i|
        {
          "id" => "call_#{i}",
          "name" => "file_read",
          "arguments" => { "file" => "#{test_dir}/file_#{i}.txt" }
        }
      end
    end

    it "executes faster than sequential would" do
      # Warm up
      parallel_executor.execute_batch(tool_calls)

      # Measure parallel execution
      parallel_time = Benchmark.realtime do
        3.times { parallel_executor.execute_batch(tool_calls) }
      end
      parallel_avg = parallel_time / 3.0

      # Measure sequential execution
      sequential_time = Benchmark.realtime do
        3.times do
          tool_calls.each { |tc| parallel_executor.execute_batch([tc]) }
        end
      end
      sequential_avg = sequential_time / 3.0

      speedup = sequential_avg / parallel_avg

      puts "\n  📊 10 FileRead Operations:"
      puts "     Parallel avg:   #{(parallel_avg * 1000).round(2)}ms"
      puts "     Sequential avg: #{(sequential_avg * 1000).round(2)}ms"
      puts "     Speedup:        #{speedup.round(2)}x"

      expect(speedup).to be >= 1.0
    end

    it "produces correct results" do
      results = parallel_executor.execute_batch(tool_calls)

      expect(results.length).to eq(10)
      results.each_with_index do |result, i|
        expect(result[:result][:error]).to be_nil
        expect(result[:result][:content]).to include("Test content for file #{i}")
      end
    end
  end

  describe "mixed read/write dependencies" do
    let(:tool_calls) do
      [
        # Batch 1: Independent reads (can run in parallel)
        { "id" => "call_1", "function" => { "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file_0.txt" } } },
        { "id" => "call_2", "function" => { "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file_1.txt" } } },
        { "id" => "call_3", "function" => { "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file_2.txt" } } },

        # Batch 2: Write (must wait for reads above)
        { "id" => "call_4", "function" => { "name" => "file_write", "arguments" => { "file" => "#{test_dir}/output.txt", "content" => "new content" } } },

        # Batch 3: Read the written file (must wait for write)
        { "id" => "call_5", "function" => { "name" => "file_read", "arguments" => { "file" => "#{test_dir}/output.txt" } } },

        # Batch 4: More independent reads (can run in parallel)
        { "id" => "call_6", "function" => { "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file_3.txt" } } },
        { "id" => "call_7", "function" => { "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file_4.txt" } } }
      ]
    end

    it "correctly identifies batch boundaries" do
      batches = dependency_analyzer.analyze(tool_calls)

      puts "\n  📊 Mixed Read/Write Dependencies:"
      puts "     Total tool calls: #{tool_calls.length}"
      puts "     Number of batches: #{batches.length}"
      batches.each_with_index do |batch, i|
        puts "     Batch #{i + 1}: #{batch.length} tool(s) - #{batch.map { |tc| tc.dig('function', 'name') }.join(', ')}"
      end

      # We expect multiple batches due to dependencies
      expect(batches.length).to be >= 2
    end

    it "executes with correct ordering and parallelism" do
      # Warm up
      parallel_executor.execute_batch(tool_calls)

      # Measure execution time
      execution_time = Benchmark.realtime do
        3.times { parallel_executor.execute_batch(tool_calls) }
      end
      avg_time = execution_time / 3.0

      puts "     Avg execution time: #{(avg_time * 1000).round(2)}ms"

      # Verify correctness
      results = parallel_executor.execute_batch(tool_calls)
      expect(results.length).to eq(7)

      # Verify the written content can be read back
      output_result = results.find { |r| r[:tool_call]["id"] == "call_5" }
      expect(output_result[:result][:content]).to eq("new content")
    end
  end

  describe "single tool call overhead" do
    let(:tool_call) do
      {
        "id" => "call_1",
        "function" => {
          "name" => "file_read",
          "arguments" => { "file" => "#{test_dir}/file_0.txt" }
        }
      }
    end

    it "has minimal overhead for single operations" do
      # Warm up
      parallel_executor.execute_batch([tool_call])

      # Measure execution time
      execution_time = Benchmark.realtime do
        100.times { parallel_executor.execute_batch([tool_call]) }
      end
      avg_time = execution_time / 100.0

      puts "\n  📊 Single Tool Call Overhead:"
      puts "     Avg execution time: #{(avg_time * 1000).round(2)}ms"

      # Single tool calls should be very fast (< 10ms on most systems)
      expect(avg_time).to be < 0.1 # 100ms is generous upper bound
    end
  end

  describe "barrier synchronization with execute_bash" do
    let(:tool_calls) do
      [
        # Batch 1: Independent reads
        { "id" => "call_1", "function" => { "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file_0.txt" } } },
        { "id" => "call_2", "function" => { "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file_1.txt" } } },

        # Batch 2: ExecuteBash (barrier - must run alone)
        { "id" => "call_3", "function" => { "name" => "execute_bash", "arguments" => { "command" => "echo 'test' > #{test_dir}/bash_output.txt" } } },

        # Batch 3: Read after bash
        { "id" => "call_4", "function" => { "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file_2.txt" } } },
        { "id" => "call_5", "function" => { "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file_3.txt" } } }
      ]
    end

    it "enforces barrier synchronization" do
      batches = dependency_analyzer.analyze(tool_calls)

      puts "\n  📊 Barrier Synchronization (ExecuteBash):"
      puts "     Total tool calls: #{tool_calls.length}"
      puts "     Number of batches: #{batches.length}"
      batches.each_with_index do |batch, i|
        puts "     Batch #{i + 1}: #{batch.length} tool(s) - #{batch.map { |tc| tc.dig('function', 'name') }.join(', ')}"
      end

      # ExecuteBash should be in its own batch
      bash_batch = batches.find { |batch| batch.any? { |tc| tc.dig("function", "name") == "execute_bash" } }
      expect(bash_batch.length).to eq(1)
      expect(batches.length).to eq(3)
    end

    it "executes correctly with barrier" do
      results = parallel_executor.execute_batch(tool_calls)

      expect(results.length).to eq(5)

      # Verify bash command executed
      bash_result = results.find { |r| r[:tool_call]["id"] == "call_3" }
      expect(bash_result[:result][:error]).to be_nil
    end
  end

  describe "comparison summary" do
    it "displays overall performance characteristics" do
      scenarios = [
        { name: "5 FileRead (parallel)", tool_count: 5, parallel: true },
        { name: "10 FileRead (parallel)", tool_count: 10, parallel: true },
        { name: "Mixed dependencies", tool_count: 7, parallel: true }
      ]

      puts "\n  📈 Performance Summary:"
      puts "  " + "=" * 60

      scenarios.each do |scenario|
        tool_calls = scenario[:tool_count].times.map do |i|
          {
            "id" => "call_#{i}",
            "function" => {
              "name" => "file_read",
              "arguments" => { "file" => "#{test_dir}/file_#{i % 20}.txt" }
            }
          }
        end

        time = Benchmark.realtime do
          5.times { parallel_executor.execute_batch(tool_calls) }
        end
        avg_time = time / 5.0

        puts "  #{scenario[:name].ljust(30)} #{(avg_time * 1000).round(2)}ms"
      end

      puts "  " + "=" * 60
    end
  end
end
