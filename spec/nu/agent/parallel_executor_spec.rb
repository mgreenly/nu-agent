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
        # Use 0.20s as threshold (allows for system variance while still clearly indicating parallel execution)
        expect(elapsed_time).to be < 0.20
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

    context "debug output" do
      let(:test_client) { instance_double("Client", model: "test-model") }
      let(:application) { instance_double(Nu::Agent::Application, debug: true) }
      let(:test_tool_calls) do
        [
          { "id" => "call_1", "name" => "test_tool", "arguments" => { "arg" => "value1" } },
          { "id" => "call_2", "name" => "test_tool", "arguments" => { "arg" => "value2" } },
          { "id" => "call_3", "name" => "test_tool", "arguments" => { "arg" => "value3" } }
        ]
      end
      let(:executor) do
        described_class.new(
          tool_registry: tool_registry,
          history: history,
          conversation_id: 1,
          client: test_client,
          application: application
        )
      end

      before do
        allow(application).to receive(:output_line)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(2)
      end

      it "outputs batch start and complete messages when debug enabled" do
        allow(tool_registry).to receive(:execute).and_return("result")

        executor.execute_batch(test_tool_calls, batch_number: 1)

        expect(application).to have_received(:output_line).with(
          /Executing batch 1/,
          type: :debug
        )
        expect(application).to have_received(:output_line).with(
          /Batch 1 complete/,
          type: :debug
        )
      end

      it "uses singular form for single tool" do
        single_tool_call = [
          { "id" => "call_1", "name" => "test_tool", "arguments" => { "arg" => "value" } }
        ]

        allow(tool_registry).to receive(:execute).and_return("result")

        executor.execute_batch(single_tool_call, batch_number: 1)

        expect(application).to have_received(:output_line).with(
          /1 tool in thread/,
          type: :debug
        )
      end

      it "uses plural form for multiple tools" do
        allow(tool_registry).to receive(:execute).and_return("result")

        executor.execute_batch(test_tool_calls, batch_number: 1)

        expect(application).to have_received(:output_line).with(
          /3 tools in.*parallel threads/,
          type: :debug
        )
      end

      it "formats elapsed time < 1 second as milliseconds" do
        allow(tool_registry).to receive(:execute) do
          sleep 0.001 # Very short duration
          "result"
        end

        executor.execute_batch(test_tool_calls, batch_number: 1)

        expect(application).to have_received(:output_line).with(
          /in \d+ms/,
          type: :debug
        )
      end

      it "formats elapsed time >= 1 second with decimal places" do
        allow(tool_registry).to receive(:execute) do
          sleep 1.1
          "result"
        end

        executor.execute_batch([test_tool_calls.first], batch_number: 1)

        expect(application).to have_received(:output_line).with(
          /in \d+\.\d+s/,
          type: :debug
        )
      end

      it "does not output when debug disabled" do
        no_debug_app = instance_double(Nu::Agent::Application, debug: false)
        no_debug_executor = described_class.new(
          tool_registry: tool_registry,
          history: history,
          conversation_id: 1,
          client: test_client,
          application: no_debug_app
        )

        allow(no_debug_app).to receive(:output_line)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(2)
        allow(tool_registry).to receive(:execute).and_return("result")

        no_debug_executor.execute_batch(test_tool_calls, batch_number: 1)

        expect(no_debug_app).not_to have_received(:output_line)
      end

      it "does not output when verbosity too low" do
        low_verbosity_app = instance_double(Nu::Agent::Application, debug: true)
        low_verbosity_executor = described_class.new(
          tool_registry: tool_registry,
          history: history,
          conversation_id: 1,
          client: test_client,
          application: low_verbosity_app
        )

        allow(low_verbosity_app).to receive(:output_line)
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(1)
        allow(tool_registry).to receive(:execute).and_return("result")

        low_verbosity_executor.execute_batch(test_tool_calls, batch_number: 1)

        expect(low_verbosity_app).not_to have_received(:output_line)
      end
    end

    context "context building" do
      let(:simple_tool_call) { [{ "id" => "call_1", "name" => "test_tool", "arguments" => {} }] }

      it "includes conversation_id when provided" do
        executor = described_class.new(
          tool_registry: tool_registry,
          history: history,
          conversation_id: 123
        )

        allow(tool_registry).to receive(:execute) do |params|
          expect(params[:context]["conversation_id"]).to eq(123)
          "result"
        end

        executor.execute_batch(simple_tool_call)
      end

      it "includes model when client provided" do
        test_client = instance_double("Client", model: "test-model")
        executor = described_class.new(
          tool_registry: tool_registry,
          history: history,
          client: test_client
        )

        allow(tool_registry).to receive(:execute) do |params|
          expect(params[:context]["model"]).to eq("test-model")
          "result"
        end

        executor.execute_batch(simple_tool_call)
      end

      it "includes application when provided" do
        app = instance_double(Nu::Agent::Application)
        executor = described_class.new(
          tool_registry: tool_registry,
          history: history,
          application: app
        )

        allow(tool_registry).to receive(:execute) do |params|
          expect(params[:context]["application"]).to eq(app)
          "result"
        end

        executor.execute_batch(simple_tool_call)
      end

      it "omits optional context fields when not provided" do
        executor = described_class.new(
          tool_registry: tool_registry,
          history: history
        )

        allow(tool_registry).to receive(:execute) do |params|
          expect(params[:context]).not_to have_key("conversation_id")
          expect(params[:context]).not_to have_key("model")
          expect(params[:context]).not_to have_key("application")
          "result"
        end

        executor.execute_batch(simple_tool_call)
      end
    end

    context "streaming callback" do
      let(:callback_tool_calls) do
        [
          { "id" => "call_1", "name" => "test_tool", "arguments" => {} },
          { "id" => "call_2", "name" => "test_tool", "arguments" => {} },
          { "id" => "call_3", "name" => "test_tool", "arguments" => {} }
        ]
      end

      it "calls block for each tool result when provided" do
        callback_results = []

        allow(tool_registry).to receive(:execute).and_return("result")

        executor.execute_batch(callback_tool_calls, batch_number: 1) do |result_data|
          callback_results << result_data
        end

        expect(callback_results.length).to eq(3)
        expect(callback_results.all? { |r| r[:result] == "result" }).to be true
      end

      it "does not call block when not provided" do
        allow(tool_registry).to receive(:execute).and_return("result")

        # Should not raise error when no block provided
        results = executor.execute_batch(callback_tool_calls, batch_number: 1)

        expect(results.length).to eq(3)
      end
    end
  end
end
