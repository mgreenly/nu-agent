# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::DependencyAnalyzer do
  let(:analyzer) { described_class.new }

  describe "#analyze" do
    context "with basic batching" do
      it "produces single batch for single tool call" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "file_read",
              "arguments" => '{"file":"/path/to/file.rb"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(1)
        expect(batches[0].size).to eq(1)
        expect(batches[0][0]["id"]).to eq("call_1")
      end

      it "batches two independent read tools together" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "file_read",
              "arguments" => '{"file":"/path/to/file1.rb"}'
            }
          },
          {
            "id" => "call_2",
            "type" => "function",
            "function" => {
              "name" => "file_read",
              "arguments" => '{"file":"/path/to/file2.rb"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(1)
        expect(batches[0].size).to eq(2)
        expect(batches[0][0]["id"]).to eq("call_1")
        expect(batches[0][1]["id"]).to eq("call_2")
      end

      it "batches two read tools on same path together" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "file_read",
              "arguments" => '{"file":"/path/to/file.rb"}'
            }
          },
          {
            "id" => "call_2",
            "type" => "function",
            "function" => {
              "name" => "file_stat",
              "arguments" => '{"file":"/path/to/file.rb"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(1)
        expect(batches[0].size).to eq(2)
        expect(batches[0][0]["id"]).to eq("call_1")
        expect(batches[0][1]["id"]).to eq("call_2")
      end

      it "creates two batches for read then write on same path" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "file_read",
              "arguments" => '{"file":"/path/to/file.rb"}'
            }
          },
          {
            "id" => "call_2",
            "type" => "function",
            "function" => {
              "name" => "file_write",
              "arguments" => '{"file":"/path/to/file.rb","content":"new content"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(2)
        expect(batches[0].size).to eq(1)
        expect(batches[0][0]["id"]).to eq("call_1")
        expect(batches[1].size).to eq(1)
        expect(batches[1][0]["id"]).to eq("call_2")
      end
    end

    context "with write dependency rules" do
      it "creates two batches for write then write on same path" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "file_write",
              "arguments" => '{"file":"/path/to/file.rb","content":"content1"}'
            }
          },
          {
            "id" => "call_2",
            "type" => "function",
            "function" => {
              "name" => "file_write",
              "arguments" => '{"file":"/path/to/file.rb","content":"content2"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(2)
        expect(batches[0].size).to eq(1)
        expect(batches[0][0]["id"]).to eq("call_1")
        expect(batches[1].size).to eq(1)
        expect(batches[1][0]["id"]).to eq("call_2")
      end

      it "creates two batches for write then read on same path" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "file_write",
              "arguments" => '{"file":"/path/to/file.rb","content":"new content"}'
            }
          },
          {
            "id" => "call_2",
            "type" => "function",
            "function" => {
              "name" => "file_read",
              "arguments" => '{"file":"/path/to/file.rb"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(2)
        expect(batches[0].size).to eq(1)
        expect(batches[0][0]["id"]).to eq("call_1")
        expect(batches[1].size).to eq(1)
        expect(batches[1][0]["id"]).to eq("call_2")
      end

      it "batches write on path A and read on path B together" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "file_write",
              "arguments" => '{"file":"/path/to/fileA.rb","content":"content"}'
            }
          },
          {
            "id" => "call_2",
            "type" => "function",
            "function" => {
              "name" => "file_read",
              "arguments" => '{"file":"/path/to/fileB.rb"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(1)
        expect(batches[0].size).to eq(2)
        expect(batches[0][0]["id"]).to eq("call_1")
        expect(batches[0][1]["id"]).to eq("call_2")
      end

      it "batches multiple writes on different paths together" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "file_write",
              "arguments" => '{"file":"/path/to/file1.rb","content":"content1"}'
            }
          },
          {
            "id" => "call_2",
            "type" => "function",
            "function" => {
              "name" => "file_write",
              "arguments" => '{"file":"/path/to/file2.rb","content":"content2"}'
            }
          },
          {
            "id" => "call_3",
            "type" => "function",
            "function" => {
              "name" => "file_write",
              "arguments" => '{"file":"/path/to/file3.rb","content":"content3"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(1)
        expect(batches[0].size).to eq(3)
        expect(batches[0][0]["id"]).to eq("call_1")
        expect(batches[0][1]["id"]).to eq("call_2")
        expect(batches[0][2]["id"]).to eq("call_3")
      end
    end

    context "with unconfined tool barriers" do
      it "forces execute_bash into solo batch" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "execute_bash",
              "arguments" => '{"command":"ls -la"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(1)
        expect(batches[0].size).to eq(1)
        expect(batches[0][0]["id"]).to eq("call_1")
      end

      it "separates tools before execute_bash into separate batch" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "file_read",
              "arguments" => '{"file":"/path/to/file.rb"}'
            }
          },
          {
            "id" => "call_2",
            "type" => "function",
            "function" => {
              "name" => "execute_bash",
              "arguments" => '{"command":"ls -la"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(2)
        expect(batches[0].size).to eq(1)
        expect(batches[0][0]["id"]).to eq("call_1")
        expect(batches[1].size).to eq(1)
        expect(batches[1][0]["id"]).to eq("call_2")
      end

      it "separates tools after execute_bash into separate batch" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "execute_bash",
              "arguments" => '{"command":"ls -la"}'
            }
          },
          {
            "id" => "call_2",
            "type" => "function",
            "function" => {
              "name" => "file_read",
              "arguments" => '{"file":"/path/to/file.rb"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(2)
        expect(batches[0].size).to eq(1)
        expect(batches[0][0]["id"]).to eq("call_1")
        expect(batches[1].size).to eq(1)
        expect(batches[1][0]["id"]).to eq("call_2")
      end

      it "gives each execute_bash call its own solo batch" do
        tool_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "execute_bash",
              "arguments" => '{"command":"ls -la"}'
            }
          },
          {
            "id" => "call_2",
            "type" => "function",
            "function" => {
              "name" => "execute_bash",
              "arguments" => '{"command":"pwd"}'
            }
          },
          {
            "id" => "call_3",
            "type" => "function",
            "function" => {
              "name" => "execute_bash",
              "arguments" => '{"command":"date"}'
            }
          }
        ]

        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(3)
        expect(batches[0].size).to eq(1)
        expect(batches[0][0]["id"]).to eq("call_1")
        expect(batches[1].size).to eq(1)
        expect(batches[1][0]["id"]).to eq("call_2")
        expect(batches[2].size).to eq(1)
        expect(batches[2][0]["id"]).to eq("call_3")
      end
    end
  end
end
