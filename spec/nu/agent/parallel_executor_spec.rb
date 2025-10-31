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

    context "edge cases" do
      it "handles empty batch" do
        results = executor.execute_batch([])

        expect(results).to be_an(Array)
        expect(results).to be_empty
      end

      it "handles large batch of tools" do
        test_dir = "/tmp/parallel_executor_large_test"
        FileUtils.mkdir_p(test_dir)

        # Create 20 tool calls
        tool_calls = (1..20).map do |i|
          File.write("#{test_dir}/file#{i}.txt", "content #{i}")
          { "id" => "call_#{i}", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file#{i}.txt" } }
        end

        results = executor.execute_batch(tool_calls)

        # All results should be present
        expect(results.length).to eq(20)

        # All should succeed
        results.each do |result_data|
          expect(result_data[:result][:error]).to be_nil
        end

        # Verify ordering is maintained
        results.each_with_index do |result_data, index|
          expect(result_data[:tool_call]["id"]).to eq("call_#{index + 1}")
        end

        FileUtils.rm_rf(test_dir)
      end

      it "handles mixed success and failure scenarios" do
        test_dir = "/tmp/parallel_executor_mixed_test"
        FileUtils.mkdir_p(test_dir)
        File.write("#{test_dir}/existing.txt", "content")

        tool_calls = [
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/existing.txt" } },
          { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/missing1.txt" } },
          { "id" => "call_3", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/existing.txt" } },
          { "id" => "call_4", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/missing2.txt" } },
          { "id" => "call_5", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/existing.txt" } }
        ]

        results = executor.execute_batch(tool_calls)

        # All results present
        expect(results.length).to eq(5)

        # Check each result
        expect(results[0][:result][:error]).to be_nil # success
        expect(results[1][:result][:error]).to match(/File not found/) # failure
        expect(results[2][:result][:error]).to be_nil # success
        expect(results[3][:result][:error]).to match(/File not found/) # failure
        expect(results[4][:result][:error]).to be_nil # success

        FileUtils.rm_rf(test_dir)
      end

      it "handles tools that modify shared resources" do
        # This test verifies thread safety when tools access shared state
        # In practice, tools shouldn't modify shared state, but we test defensive behavior
        test_file = "/tmp/parallel_executor_shared.txt"
        File.write(test_file, "initial")

        # Create 5 concurrent reads of the same file
        tool_calls = (1..5).map do |i|
          { "id" => "call_#{i}", "name" => "file_read", "arguments" => { "file" => test_file } }
        end

        # Should not raise any thread safety errors
        results = executor.execute_batch(tool_calls)

        expect(results.length).to eq(5)
        results.each do |result_data|
          expect(result_data[:result][:error]).to be_nil
        end

        File.delete(test_file)
      end
    end

    context "batch and thread tracking" do
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

      it "includes batch number in result_data when batch number provided" do
        results = executor.execute_batch(tool_calls, batch_number: 2)

        expect(results.length).to eq(3)
        results.each do |result_data|
          expect(result_data[:batch]).to eq(2)
        end
      end

      it "includes thread numbers in result_data starting from 1" do
        results = executor.execute_batch(tool_calls, batch_number: 1)

        expect(results.length).to eq(3)
        # Each result should have a unique thread number from 1 to 3
        thread_numbers = results.map { |r| r[:thread] }
        expect(thread_numbers.sort).to eq([1, 2, 3])
      end

      it "does not include batch/thread when batch number not provided" do
        results = executor.execute_batch(tool_calls)

        expect(results.length).to eq(3)
        results.each do |result_data|
          expect(result_data).not_to have_key(:batch)
          expect(result_data).not_to have_key(:thread)
        end
      end

      it "includes batch and thread in all results including errors" do
        tool_calls_with_error = [
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file1.txt" } },
          { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/nonexistent.txt" } },
          { "id" => "call_3", "name" => "file_read", "arguments" => { "file" => "#{test_dir}/file3.txt" } }
        ]

        results = executor.execute_batch(tool_calls_with_error, batch_number: 3)

        expect(results.length).to eq(3)
        results.each do |result_data|
          expect(result_data[:batch]).to eq(3)
          expect(result_data[:thread]).to be_between(1, 3)
        end
      end
    end
  end
end
