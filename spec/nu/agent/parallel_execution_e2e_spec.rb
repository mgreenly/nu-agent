# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass, Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
RSpec.describe "Parallel Tool Execution End-to-End" do
  # Shared execution tracker
  class ExecutionTracker
    attr_reader :executions

    def initialize
      @executions = []
      @mutex = Mutex.new
    end

    def record(tool_name, arguments)
      @mutex.synchronize do
        @executions << [tool_name, arguments]
      end
    end

    def reset
      @mutex.synchronize do
        @executions = []
      end
    end
  end

  # Define test tool classes
  class TestFileReadTool
    attr_accessor :tracker

    def name
      "file_read"
    end

    def description
      "Test file read tool"
    end

    def parameters
      { file: { type: "string", required: true } }
    end

    def operation_type
      :read
    end

    def scope
      :confined
    end

    def execute(arguments:, **)
      @tracker&.record("file_read", arguments)
      { content: "file contents", file: arguments[:file] || arguments["file"] }
    end
  end

  class TestFileWriteTool
    attr_accessor :tracker

    def name
      "file_write"
    end

    def description
      "Test file write tool"
    end

    def parameters
      { file: { type: "string", required: true }, content: { type: "string", required: true } }
    end

    def operation_type
      :write
    end

    def scope
      :confined
    end

    def execute(arguments:, **)
      @tracker&.record("file_write", arguments)
      { content: "written", file: arguments[:file] || arguments["file"] }
    end
  end

  class TestExecuteBashTool
    attr_accessor :tracker

    def name
      "execute_bash"
    end

    def description
      "Test bash execution tool"
    end

    def parameters
      { command: { type: "string", required: true } }
    end

    def operation_type
      :write
    end

    def scope
      :unconfined
    end

    def execute(arguments:, **)
      @tracker&.record("execute_bash", arguments)
      { content: "command output" }
    end
  end

  class TestSlowReadTool
    def name
      "slow_read"
    end

    def description
      "Test slow read tool"
    end

    def parameters
      { file: { type: "string", required: true } }
    end

    def operation_type
      :read
    end

    def scope
      :confined
    end

    def execute(arguments:, **)
      sleep(0.1) # Simulate slow operation
      { content: "slow file contents", file: arguments[:file] || arguments["file"] }
    end
  end

  class TestFailingTool
    def name
      "failing_tool"
    end

    def description
      "Test tool that fails"
    end

    def parameters
      {}
    end

    def operation_type
      :read
    end

    def scope
      :confined
    end

    def execute(**)
      raise StandardError, "Tool failed"
    end
  end

  class TestTimeoutTool
    def name
      "timeout_tool"
    end

    def description
      "Test tool that times out"
    end

    def parameters
      {}
    end

    def operation_type
      :read
    end

    def scope
      :confined
    end

    def execute(**)
      sleep(10) # Simulate very long operation
      { content: "should not reach here" }
    end
  end

  let(:client) { instance_double(Nu::Agent::Clients::Anthropic, model: "claude-sonnet-4-5", name: "Anthropic") }
  let(:history) { instance_double(Nu::Agent::History) }
  let(:formatter) { instance_double(Nu::Agent::Formatter) }
  let(:console) { instance_double(Nu::Agent::ConsoleIO) }
  let(:tool_registry) { Nu::Agent::ToolRegistry.new }
  let(:application) do
    instance_double(Nu::Agent::Application, formatter: formatter, console: console, debug: false)
  end
  let(:execution_tracker) { ExecutionTracker.new }

  let(:file_read_tool) { TestFileReadTool.new.tap { |t| t.tracker = execution_tracker } }
  let(:file_write_tool) { TestFileWriteTool.new.tap { |t| t.tracker = execution_tracker } }
  let(:execute_bash_tool) { TestExecuteBashTool.new.tap { |t| t.tracker = execution_tracker } }
  let(:slow_read_tool) { TestSlowReadTool.new }

  let(:orchestrator) do
    Nu::Agent::ToolCallOrchestrator.new(
      client: client,
      history: history,
      exchange_info: { conversation_id: 1, exchange_id: 1 },
      tool_registry: tool_registry,
      application: application
    )
  end

  before do
    # Register test tools
    tool_registry.register(file_read_tool)
    tool_registry.register(file_write_tool)
    tool_registry.register(execute_bash_tool)
    tool_registry.register(slow_read_tool)
  end

  describe "complete chat loop with parallel tool calls" do
    it "executes a full conversation with multiple tool rounds" do
      messages = [{ "role" => "user", "content" => "Read three files" }]

      # First turn: LLM calls 3 file_read tools
      tool_call_response1 = {
        "content" => "",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 10, "output" => 5 },
        "spend" => 0.001,
        "tool_calls" => [
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/path/to/file1" } },
          { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "/path/to/file2" } },
          { "id" => "call_3", "name" => "file_read", "arguments" => { "file" => "/path/to/file3" } }
        ]
      }

      # Second turn: LLM analyzes and calls file_write
      tool_call_response2 = {
        "content" => "Let me save this",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 20, "output" => 8 },
        "spend" => 0.002,
        "tool_calls" => [
          { "id" => "call_4", "name" => "file_write", "arguments" => { "file" => "/output", "content" => "result" } }
        ]
      }

      # Final response
      final_response = {
        "content" => "Done! I read three files and saved the result.",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 30, "output" => 12 },
        "spend" => 0.003
      }

      allow(client).to receive(:send_message).and_return(
        tool_call_response1,
        tool_call_response2,
        final_response
      )
      allow(history).to receive(:add_message)
      allow(formatter).to receive(:display_message_created)
      allow(console).to receive(:hide_spinner)
      allow(console).to receive(:show_spinner)
      allow(application).to receive(:send).with(:output_line, "Let me save this")

      result = orchestrator.execute(messages: messages, tools: [])

      expect(result[:error]).to be false
      expect(result[:metrics][:tool_call_count]).to eq(4)
      expect(result[:metrics][:message_count]).to eq(3)
      expect(result[:response]["content"]).to eq("Done! I read three files and saved the result.")
    end
  end

  describe "complex scenario with 10 tools and mixed dependencies" do
    it "correctly batches and executes tools with various dependency patterns" do
      messages = [{ "role" => "user", "content" => "Complex task" }]

      tool_call_response = {
        "content" => "",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 10, "output" => 5 },
        "spend" => 0.001,
        "tool_calls" => [
          # Batch 1: Independent reads
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/a" } },
          { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "/b" } },
          { "id" => "call_3", "name" => "file_read", "arguments" => { "file" => "/c" } },

          # Batch 2: Write to /a (conflicts with earlier read)
          { "id" => "call_4", "name" => "file_write", "arguments" => { "file" => "/a", "content" => "new" } },

          # Batch 3: Read from /a (conflicts with write)
          { "id" => "call_5", "name" => "file_read", "arguments" => { "file" => "/a" } },

          # Batch 4: Independent reads on different paths
          { "id" => "call_6", "name" => "file_read", "arguments" => { "file" => "/d" } },
          { "id" => "call_7", "name" => "file_read", "arguments" => { "file" => "/e" } },

          # Batch 5: Bash (unconfined, must be solo)
          { "id" => "call_8", "name" => "execute_bash", "arguments" => { "command" => "ls" } },

          # Batch 6: More reads after bash
          { "id" => "call_9", "name" => "file_read", "arguments" => { "file" => "/f" } },
          { "id" => "call_10", "name" => "file_read", "arguments" => { "file" => "/g" } }
        ]
      }

      final_response = {
        "content" => "Complex task completed",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 15, "output" => 8 },
        "spend" => 0.002
      }

      allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
      allow(history).to receive(:add_message)
      allow(formatter).to receive(:display_message_created)

      result = orchestrator.execute(messages: messages, tools: [])

      expect(result[:error]).to be false
      expect(result[:metrics][:tool_call_count]).to eq(10)

      # Verify execution order respects dependencies
      execution_order = execution_tracker.executions.map { |name, _args| name }

      # Batch 1 completes before batch 2
      call_4_index = execution_order.index("file_write")
      expect(call_4_index).not_to be_nil
      expect(execution_order[0...call_4_index].count("file_read")).to eq(3)

      # execute_bash is isolated
      bash_index = execution_order.index("execute_bash")
      expect(bash_index).to be >= 5 # After at least 5 earlier calls
    end
  end

  describe "verify actual parallelism (timing-based)" do
    it "executes independent tools in parallel, reducing total time" do
      messages = [{ "role" => "user", "content" => "Read slow files" }]

      tool_call_response = {
        "content" => "",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 10, "output" => 5 },
        "spend" => 0.001,
        "tool_calls" => [
          { "id" => "call_1", "name" => "slow_read", "arguments" => { "file" => "/a" } },
          { "id" => "call_2", "name" => "slow_read", "arguments" => { "file" => "/b" } },
          { "id" => "call_3", "name" => "slow_read", "arguments" => { "file" => "/c" } }
        ]
      }

      final_response = {
        "content" => "Done",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 15, "output" => 8 },
        "spend" => 0.002
      }

      allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
      allow(history).to receive(:add_message)
      allow(formatter).to receive(:display_message_created)

      start_time = Time.now
      result = orchestrator.execute(messages: messages, tools: [])
      elapsed = Time.now - start_time

      expect(result[:error]).to be false
      expect(result[:metrics][:tool_call_count]).to eq(3)

      # If sequential, would take ~0.3s (3 × 0.1s)
      # If parallel, should take ~0.1s (max of the three)
      # Allow some overhead, but verify it's closer to parallel than sequential
      expect(elapsed).to be < 0.25 # Should be much less than sequential time
    end
  end

  describe "error in one tool doesn't affect others in batch" do
    before do
      # Register a tool that raises an error
      tool_registry.register(TestFailingTool.new)
    end

    it "continues execution and captures the error" do
      messages = [{ "role" => "user", "content" => "Test error handling" }]

      tool_call_response = {
        "content" => "",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 10, "output" => 5 },
        "spend" => 0.001,
        "tool_calls" => [
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/a" } },
          { "id" => "call_2", "name" => "failing_tool", "arguments" => {} },
          { "id" => "call_3", "name" => "file_read", "arguments" => { "file" => "/b" } }
        ]
      }

      final_response = {
        "content" => "Handled the error",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 15, "output" => 8 },
        "spend" => 0.002
      }

      saved_results = []
      allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
      allow(formatter).to receive(:display_message_created)
      allow(history).to receive(:add_message) do |params|
        saved_results << params if params[:role] == "tool"
      end

      result = orchestrator.execute(messages: messages, tools: [])

      expect(result[:error]).to be false
      expect(result[:metrics][:tool_call_count]).to eq(3)

      # All three tools should have results saved
      expect(saved_results.length).to eq(3)

      # The failing tool should have an error result
      failing_result = saved_results.find { |r| r[:tool_call_id] == "call_2" }
      expect(failing_result[:tool_result]["result"]).to have_key(:error)
      expect(failing_result[:tool_result]["result"][:error]).to include("Exception")

      # Other tools should succeed
      success_results = saved_results.reject { |r| r[:tool_call_id] == "call_2" }
      expect(success_results.length).to eq(2)
      success_results.each do |r|
        expect(r[:tool_result]["result"]).not_to have_key(:error)
      end
    end
  end

  describe "empty tool_calls array edge case" do
    it "handles empty tool_calls array gracefully" do
      messages = [{ "role" => "user", "content" => "Test" }]

      tool_call_response = {
        "content" => "Thinking...",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 10, "output" => 5 },
        "spend" => 0.001,
        "tool_calls" => []
      }

      final_response = {
        "content" => "Done",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 15, "output" => 8 },
        "spend" => 0.002
      }

      allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
      allow(history).to receive(:add_message)
      allow(formatter).to receive(:display_message_created)
      allow(console).to receive(:hide_spinner)
      allow(console).to receive(:show_spinner)
      allow(application).to receive(:send).with(:output_line, "Thinking...")

      result = orchestrator.execute(messages: messages, tools: [])

      expect(result[:error]).to be false
      expect(result[:metrics][:tool_call_count]).to eq(0)
    end
  end

  describe "all tools in single batch (all independent reads)" do
    it "executes all tools in parallel in one batch" do
      messages = [{ "role" => "user", "content" => "Read many files" }]

      tool_calls = (1..5).map do |i|
        { "id" => "call_#{i}", "name" => "file_read", "arguments" => { "file" => "/file#{i}" } }
      end

      tool_call_response = {
        "content" => "",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 10, "output" => 5 },
        "spend" => 0.001,
        "tool_calls" => tool_calls
      }

      final_response = {
        "content" => "All files read",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 15, "output" => 8 },
        "spend" => 0.002
      }

      allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
      allow(history).to receive(:add_message)
      allow(formatter).to receive(:display_message_created)

      result = orchestrator.execute(messages: messages, tools: [])

      expect(result[:error]).to be false
      expect(result[:metrics][:tool_call_count]).to eq(5)
    end
  end

  describe "all tools in separate batches (chain of dependencies)" do
    it "executes tools sequentially when all have dependencies" do
      messages = [{ "role" => "user", "content" => "Sequential operations" }]

      tool_call_response = {
        "content" => "",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 10, "output" => 5 },
        "spend" => 0.001,
        "tool_calls" => [
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/a" } },
          { "id" => "call_2", "name" => "file_write", "arguments" => { "file" => "/a", "content" => "v1" } },
          { "id" => "call_3", "name" => "file_read", "arguments" => { "file" => "/a" } },
          { "id" => "call_4", "name" => "file_write", "arguments" => { "file" => "/a", "content" => "v2" } },
          { "id" => "call_5", "name" => "file_read", "arguments" => { "file" => "/a" } }
        ]
      }

      final_response = {
        "content" => "Sequential completed",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 15, "output" => 8 },
        "spend" => 0.002
      }

      allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
      allow(history).to receive(:add_message)
      allow(formatter).to receive(:display_message_created)

      result = orchestrator.execute(messages: messages, tools: [])

      expect(result[:error]).to be false
      expect(result[:metrics][:tool_call_count]).to eq(5)

      # Verify strict ordering due to dependencies
      execution_order = execution_tracker.executions
      expect(execution_order[0][0]).to eq("file_read")
      expect(execution_order[1][0]).to eq("file_write")
      expect(execution_order[2][0]).to eq("file_read")
      expect(execution_order[3][0]).to eq("file_write")
      expect(execution_order[4][0]).to eq("file_read")
    end
  end

  describe "execute_bash in middle of tool sequence" do
    it "isolates bash execution as a barrier" do
      messages = [{ "role" => "user", "content" => "Mix of operations" }]

      tool_call_response = {
        "content" => "",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 10, "output" => 5 },
        "spend" => 0.001,
        "tool_calls" => [
          { "id" => "call_1", "name" => "file_read", "arguments" => { "file" => "/a" } },
          { "id" => "call_2", "name" => "file_read", "arguments" => { "file" => "/b" } },
          { "id" => "call_3", "name" => "execute_bash", "arguments" => { "command" => "ls" } },
          { "id" => "call_4", "name" => "file_read", "arguments" => { "file" => "/c" } },
          { "id" => "call_5", "name" => "file_read", "arguments" => { "file" => "/d" } }
        ]
      }

      final_response = {
        "content" => "Mixed operations completed",
        "model" => "claude-sonnet-4-5",
        "tokens" => { "input" => 15, "output" => 8 },
        "spend" => 0.002
      }

      allow(client).to receive(:send_message).and_return(tool_call_response, final_response)
      allow(history).to receive(:add_message)
      allow(formatter).to receive(:display_message_created)

      result = orchestrator.execute(messages: messages, tools: [])

      expect(result[:error]).to be false
      expect(result[:metrics][:tool_call_count]).to eq(5)

      # Verify bash is isolated: all reads before complete, then bash, then reads after
      execution_order = execution_tracker.executions.map { |name, _args| name }
      bash_index = execution_order.index("execute_bash")
      expect(bash_index).to eq(2) # After the two reads
      expect(execution_order[0..1]).to all(eq("file_read"))
      expect(execution_order[3..4]).to all(eq("file_read"))
    end
  end
end
# rubocop:enable RSpec/DescribeClass, Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
