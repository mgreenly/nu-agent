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
  end
end
