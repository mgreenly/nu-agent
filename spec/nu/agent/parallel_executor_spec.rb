# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Nu::Agent::ParallelExecutor do
  let(:tool_registry) { Nu::Agent::ToolRegistry.new }
  let(:history) { instance_double(Nu::Agent::History) }
  let(:executor) { described_class.new(tool_registry: tool_registry, history: history) }

  describe "#execute_batch" do
    context "with a single tool call" do
      let(:tool_call) do
        {
          "id" => "call_1",
          "name" => "file_read",
          "arguments" => { "file" => "/tmp/test.txt" }
        }
      end

      it "executes the tool call and returns the result" do
        # Create a temporary test file
        test_file = "/tmp/test.txt"
        FileUtils.mkdir_p("/tmp")
        File.write(test_file, "test content")

        results = executor.execute_batch([tool_call])

        expect(results).to be_an(Array)
        expect(results.length).to eq(1)
        expect(results[0]).to include(
          tool_call: tool_call,
          result: hash_including(
            file: test_file,
            content: String
          )
        )
        expect(results[0][:result][:error]).to be_nil

        # Clean up
        File.delete(test_file)
      end

      it "preserves tool_call and result in output" do
        # Create a temporary test file
        test_file = "/tmp/test.txt"
        FileUtils.mkdir_p("/tmp")
        File.write(test_file, "test content")

        results = executor.execute_batch([tool_call])

        expect(results[0][:tool_call]).to eq(tool_call)
        expect(results[0][:result]).to be_a(Hash)
        expect(results[0][:result][:error]).to be_nil

        # Clean up
        File.delete(test_file)
      end

      it "handles tool execution errors gracefully" do
        results = executor.execute_batch([tool_call])

        expect(results).to be_an(Array)
        expect(results.length).to eq(1)
        expect(results[0]).to include(
          tool_call: tool_call,
          result: hash_including(
            error: /File not found/
          )
        )
        expect(results[0][:result][:content]).to be_nil
      end
    end

    context "with multiple independent tool calls" do
      let(:test_dir) { "/tmp/parallel_executor_test" }
      let(:tool_calls) do
        [
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file1.txt" } },
          { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file2.txt" } },
          { "id" => "call_3", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file3.txt" } }
        ]
      end

      before do
        FileUtils.mkdir_p(test_dir)
        File.write("#{test_dir}/file1.txt", "content 1")
        File.write("#{test_dir}/file2.txt", "content 2")
        File.write("#{test_dir}/file3.txt", "content 3")
      end

      after do
        FileUtils.rm_rf(test_dir)
      end

      it "executes 3 independent tools in parallel" do
        # Mock Thread to track parallel execution
        original_new = Thread.method(:new)
        threads = []

        allow(Thread).to receive(:new) do |&block|
          thread = original_new.call(&block)
          threads << thread
          thread
        end

        results = executor.execute_batch(tool_calls)

        # Verify that threads were created (indicating parallel execution)
        expect(threads.length).to be > 0

        # Verify all results returned
        expect(results.length).to eq(3)
      end

      it "waits for all tools to complete before returning" do
        results = executor.execute_batch(tool_calls)

        # All results should be present
        expect(results.length).to eq(3)

        # All results should have completed successfully
        results.each do |result_data|
          expect(result_data[:result][:error]).to be_nil
          expect(result_data[:result][:content]).to be_a(String)
        end
      end

      it "returns results in original order" do
        results = executor.execute_batch(tool_calls)

        # Verify results match original tool_call order
        expect(results[0][:tool_call]["id"]).to eq("call_1")
        expect(results[1][:tool_call]["id"]).to eq("call_2")
        expect(results[2][:tool_call]["id"]).to eq("call_3")
      end

      it "actually executes tools in parallel (timing-based verification)" do
        # Create tool calls that have measurable execution time
        slow_tool_calls = [
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file1.txt" } },
          { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file2.txt" } },
          { "id" => "call_3", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file3.txt" } }
        ]

        # Inject delays to make execution time measurable
        allow(tool_registry).to receive(:execute) do |**args|
          sleep(0.05) # 50ms delay per tool
          Nu::Agent::Tools::FileRead.new.execute(arguments: args[:arguments])
        end

        # Parallel execution of 3 tools with 50ms each should take ~50ms total
        # Sequential execution would take ~150ms
        start_time = Time.now
        executor.execute_batch(slow_tool_calls)
        elapsed_time = Time.now - start_time

        # If truly parallel, should be closer to 0.05s than 0.15s
        # Use 0.12s as threshold (between 0.05 and 0.15)
        expect(elapsed_time).to be < 0.12
      end
    end

    context "thread safety and exception handling" do
      let(:test_dir) { "/tmp/parallel_executor_test" }

      before do
        FileUtils.mkdir_p(test_dir)
        File.write("#{test_dir}/good_file.txt", "content")
      end

      after do
        FileUtils.rm_rf(test_dir)
      end

      it "handles exception in one thread without crashing other threads" do
        tool_calls = [
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/good_file.txt" } },
          { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/nonexistent.txt" } },
          { "id" => "call_3", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/good_file.txt" } }
        ]

        # Should not raise an exception
        results = executor.execute_batch(tool_calls)

        # All results should be returned
        expect(results.length).to eq(3)

        # First and third should succeed
        expect(results[0][:result][:error]).to be_nil
        expect(results[2][:result][:error]).to be_nil

        # Second should have error
        expect(results[1][:result][:error]).to match(/File not found/)
      end

      it "captures unhandled exceptions in threads and returns as error results" do
        tool_calls = [
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/good_file.txt" } },
          { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/good_file.txt" } }
        ]

        # Simulate an unhandled exception in tool execution
        call_count = 0
        allow(tool_registry).to receive(:execute) do |**args|
          call_count += 1
          raise StandardError, "Simulated crash" if call_count == 1

          Nu::Agent::Tools::FileRead.new.execute(arguments: args[:arguments])
        end

        # Should not propagate exception to caller, but return it as error result
        results = executor.execute_batch(tool_calls)

        expect(results.length).to eq(2)

        # First result should have the exception as an error
        expect(results[0][:result][:error]).to match(/Simulated crash/)
        expect(results[0][:result][:exception]).to be_a(StandardError)

        # Second result should succeed
        expect(results[1][:result][:error]).to be_nil
      end

      it "maintains result ordering even when threads complete out of order" do
        tool_calls = [
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/good_file.txt" } },
          { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/good_file.txt" } },
          { "id" => "call_3", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/good_file.txt" } }
        ]

        # Make threads complete in reverse order
        call_count = 0
        allow(tool_registry).to receive(:execute) do |**args|
          call_count += 1
          # First call sleeps longest, last call completes first
          sleep(0.01 * (4 - call_count))
          Nu::Agent::Tools::FileRead.new.execute(arguments: args[:arguments])
        end

        results = executor.execute_batch(tool_calls)

        # Despite reverse completion order, results should match original order
        expect(results[0][:tool_call]["id"]).to eq("call_1")
        expect(results[1][:tool_call]["id"]).to eq("call_2")
        expect(results[2][:tool_call]["id"]).to eq("call_3")
      end
    end
  end
end
