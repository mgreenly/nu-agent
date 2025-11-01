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
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/file.rb"}'
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
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/file1.rb"}'
          },
          {
            "id" => "call_2",
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/file2.rb"}'
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
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/file.rb"}'
          },
          {
            "id" => "call_2",
            "name" => "file_stat",
            "arguments" => '{"file":"/path/to/file.rb"}'
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
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/file.rb"}'
          },
          {
            "id" => "call_2",
            "name" => "file_write",
            "arguments" => '{"file":"/path/to/file.rb","content":"new content"}'
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
            "name" => "file_write",
            "arguments" => '{"file":"/path/to/file.rb","content":"content1"}'
          },
          {
            "id" => "call_2",
            "name" => "file_write",
            "arguments" => '{"file":"/path/to/file.rb","content":"content2"}'
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
            "name" => "file_write",
            "arguments" => '{"file":"/path/to/file.rb","content":"new content"}'
          },
          {
            "id" => "call_2",
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/file.rb"}'
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
            "name" => "file_write",
            "arguments" => '{"file":"/path/to/fileA.rb","content":"content"}'
          },
          {
            "id" => "call_2",
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/fileB.rb"}'
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
            "name" => "file_write",
            "arguments" => '{"file":"/path/to/file1.rb","content":"content1"}'
          },
          {
            "id" => "call_2",
            "name" => "file_write",
            "arguments" => '{"file":"/path/to/file2.rb","content":"content2"}'
          },
          {
            "id" => "call_3",
            "name" => "file_write",
            "arguments" => '{"file":"/path/to/file3.rb","content":"content3"}'
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
            "name" => "execute_bash",
            "arguments" => '{"command":"ls -la"}'
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
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/file.rb"}'
          },
          {
            "id" => "call_2",
            "name" => "execute_bash",
            "arguments" => '{"command":"ls -la"}'
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
            "name" => "execute_bash",
            "arguments" => '{"command":"ls -la"}'
          },
          {
            "id" => "call_2",
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/file.rb"}'
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
            "name" => "execute_bash",
            "arguments" => '{"command":"ls -la"}'
          },
          {
            "id" => "call_2",
            "name" => "execute_bash",
            "arguments" => '{"command":"pwd"}'
          },
          {
            "id" => "call_3",
            "name" => "execute_bash",
            "arguments" => '{"command":"date"}'
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

    context "with comprehensive scenarios" do
      it "handles complex mix of 10+ tools with various dependencies" do
        tool_calls = [
          # Batch 1: Independent reads
          { "id" => "call_1", "name" => "file_read", "arguments" => '{"file":"/path/a.rb"}' },
          { "id" => "call_2", "name" => "file_read", "arguments" => '{"file":"/path/b.rb"}' },
          { "id" => "call_3", "name" => "file_stat", "arguments" => '{"file":"/path/c.rb"}' },
          # Batch 2: Write on a.rb (conflicts with call_1)
          { "id" => "call_4", "name" => "file_write",
            "arguments" => '{"file":"/path/a.rb","content":"new"}' },
          # Batch 3: Reads on different paths
          { "id" => "call_5", "name" => "file_read", "arguments" => '{"file":"/path/d.rb"}' },
          { "id" => "call_6", "name" => "file_read", "arguments" => '{"file":"/path/e.rb"}' },
          # Batch 4: Execute bash (barrier)
          { "id" => "call_7", "name" => "execute_bash", "arguments" => '{"command":"ls"}' },
          # Batch 5: Reads after barrier
          { "id" => "call_8", "name" => "file_read", "arguments" => '{"file":"/path/f.rb"}' },
          { "id" => "call_9", "name" => "file_read", "arguments" => '{"file":"/path/g.rb"}' },
          # Batch 6: Write on f.rb
          { "id" => "call_10", "name" => "file_write",
            "arguments" => '{"file":"/path/f.rb","content":"x"}' },
          # Batch 7: Read after write
          { "id" => "call_11", "name" => "file_read", "arguments" => '{"file":"/path/h.rb"}' }
        ]

        batches = analyzer.analyze(tool_calls)

        # Expected batching:
        # Batch 1: call_1, call_2, call_3 (independent reads)
        # Batch 2: call_4 (write a.rb, conflicts with prior read), call_5, call_6 (reads on different paths)
        # Batch 3: call_7 (execute_bash - barrier)
        # Batch 4: call_8, call_9 (reads after barrier)
        # Batch 5: call_10 (write f.rb, conflicts with prior read), call_11 (read on different path)
        expect(batches.size).to eq(5)
        expect(batches[0].map { |tc| tc["id"] }).to eq(%w[call_1 call_2 call_3])
        expect(batches[1].map { |tc| tc["id"] }).to eq(%w[call_4 call_5 call_6])
        expect(batches[2].map { |tc| tc["id"] }).to eq(["call_7"])
        expect(batches[3].map { |tc| tc["id"] }).to eq(%w[call_8 call_9])
        expect(batches[4].map { |tc| tc["id"] }).to eq(%w[call_10 call_11])
      end

      it "handles database tools (different resource type)" do
        tool_calls = [
          {
            "id" => "call_1",
            "name" => "database_query",
            "arguments" => '{"query":"SELECT * FROM users"}'
          },
          {
            "id" => "call_2",
            "name" => "database_query",
            "arguments" => '{"query":"SELECT * FROM posts"}'
          },
          {
            "id" => "call_3",
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/file.rb"}'
          }
        ]

        batches = analyzer.analyze(tool_calls)

        # Database queries and file reads can batch together (different resource types)
        expect(batches.size).to eq(1)
        expect(batches[0].size).to eq(3)
      end

      it "handles tools with no extractable paths" do
        tool_calls = [
          {
            "id" => "call_1",
            "name" => "file_glob",
            "arguments" => '{"pattern":"*.rb"}'
          },
          {
            "id" => "call_2",
            "name" => "file_grep",
            "arguments" => '{"pattern":"TODO","path":"."}'
          },
          {
            "id" => "call_3",
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/file.rb"}'
          }
        ]

        batches = analyzer.analyze(tool_calls)

        # Tools without extractable paths can batch with other reads
        expect(batches.size).to eq(1)
        expect(batches[0].size).to eq(3)
      end

      it "handles empty tool_calls array" do
        tool_calls = []

        batches = analyzer.analyze(tool_calls)

        expect(batches).to eq([])
      end

      it "handles nil tool_calls" do
        tool_calls = nil

        batches = analyzer.analyze(tool_calls)

        expect(batches).to eq([])
      end

      it "handles tools with invalid arguments" do
        tool_calls = [
          {
            "id" => "call_1",
            "name" => "file_read",
            "arguments" => nil
          },
          {
            "id" => "call_2",
            "name" => "file_read",
            "arguments" => '{"file":"/path/to/file.rb"}'
          }
        ]

        batches = analyzer.analyze(tool_calls)

        # Tools with invalid arguments can still batch (treated as no paths)
        expect(batches.size).to eq(1)
        expect(batches[0].size).to eq(2)
      end

      it "handles mixed file operations (copy, move, delete)" do
        tool_calls = [
          {
            "id" => "call_1",
            "name" => "file_copy",
            "arguments" => '{"source":"/a.rb","destination":"/b.rb"}'
          },
          {
            "id" => "call_2",
            "name" => "file_move",
            "arguments" => '{"source":"/c.rb","destination":"/d.rb"}'
          },
          {
            "id" => "call_3",
            "name" => "file_delete",
            "arguments" => '{"file":"/e.rb"}'
          },
          {
            "id" => "call_4",
            "name" => "file_read",
            "arguments" => '{"file":"/a.rb"}'
          }
        ]

        batches = analyzer.analyze(tool_calls)

        # First 3 writes can batch together (different paths)
        # Read on /a.rb conflicts with copy that writes to /b.rb but reads from /a.rb
        # So call_4 should be in a separate batch
        expect(batches.size).to eq(2)
        expect(batches[0].map { |tc| tc["id"] }).to eq(%w[call_1 call_2 call_3])
        expect(batches[1].map { |tc| tc["id"] }).to eq(["call_4"])
      end
    end

    context "with invalid JSON arguments" do
      it "handles malformed JSON gracefully by using empty hash" do
        tool_calls = [
          {
            "id" => "call_1",
            "name" => "file_read",
            "arguments" => "not valid json{{"
          }
        ]

        # Should not raise error, should batch the tool call anyway
        batches = analyzer.analyze(tool_calls)

        expect(batches.size).to eq(1)
        expect(batches[0].size).to eq(1)
        expect(batches[0][0]["id"]).to eq("call_1")
      end
    end
  end
end
