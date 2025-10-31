# frozen_string_literal: true

module Nu
  module Agent
    # ParallelExecutor handles execution of tool call batches
    # Initially executes tools sequentially, with parallel execution to be added later
    class ParallelExecutor
      def initialize(tool_registry:, history:, conversation_id: nil, client: nil, application: nil)
        @tool_registry = tool_registry
        @history = history
        @conversation_id = conversation_id
        @client = client
        @application = application
      end

      # Execute a batch of tool calls and return results
      # @param tool_calls [Array<Hash>] Array of tool call hashes
      # @return [Array<Hash>] Array of results with format: { tool_call: ..., result: ... }
      def execute_batch(tool_calls)
        tool_calls.map do |tool_call|
          result = execute_tool(tool_call)
          { tool_call: tool_call, result: result }
        end
      end

      private

      def execute_tool(tool_call)
        @tool_registry.execute(
          name: tool_call["name"],
          arguments: tool_call["arguments"],
          history: @history,
          context: build_context
        )
      end

      def build_context
        context = {}
        context["conversation_id"] = @conversation_id if @conversation_id
        context["model"] = @client.model if @client
        context["application"] = @application if @application
        context
      end
    end
  end
end
