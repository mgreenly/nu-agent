# frozen_string_literal: true

module Nu
  module Agent
    # Manages the tool calling loop with LLM
    class ToolCallOrchestrator
      def initialize(client:, history:, exchange_info:, tool_registry:, application:)
        @client = client
        @history = history
        @formatter = application.formatter
        @console = application.console
        @conversation_id = exchange_info[:conversation_id]
        @exchange_id = exchange_info[:exchange_id]
        @tool_registry = tool_registry
        @application = application
      end

      # Execute the tool calling loop
      # Returns a hash with :error, :response, and :metrics keys
      def execute(messages:, tools:, system_prompt: nil)
        metrics = {
          tokens_input: 0,
          tokens_output: 0,
          spend: 0.0,
          message_count: 0,
          tool_call_count: 0
        }

        loop do
          # Send request to LLM
          send_params = { messages: messages, tools: tools }
          send_params[:system_prompt] = system_prompt if system_prompt
          response = @client.send_message(**send_params)

          # Check for errors first
          if response["error"]
            handle_error_response(response, metrics)
            return { error: true, response: response, metrics: metrics }
          end

          # Update metrics
          update_metrics(metrics, response)

          # Check for tool calls
          return { error: false, response: response, metrics: metrics } unless response["tool_calls"]

          handle_tool_calls(response, messages, metrics)
          # Continue loop to get next LLM response

          # No tool calls - this is the final response
        end
      end

      private

      def handle_error_response(response, _metrics)
        # Save error message (unredacted so user can see it)
        @history.add_message(
          conversation_id: @conversation_id,
          exchange_id: @exchange_id,
          actor: "api_error",
          role: "assistant",
          content: response["content"],
          model: response["model"],
          error: response["error"],
          redacted: false
        )
        @formatter.display_message_created(
          actor: "api_error",
          role: "assistant",
          content: response["content"]
        )
      end

      def update_metrics(metrics, response)
        # tokens_input is max (largest context window used)
        # tokens_output is sum (total tokens generated)
        metrics[:tokens_input] = [metrics[:tokens_input], response["tokens"]["input"] || 0].max
        metrics[:tokens_output] += response["tokens"]["output"] || 0
        metrics[:spend] += response["spend"] || 0.0
        metrics[:message_count] += 1
      end

      def handle_tool_calls(response, messages, metrics)
        save_tool_call_message(response)
        display_tool_call_message(response)
        display_content_if_present(response["content"])

        metrics[:tool_call_count] += response["tool_calls"].length
        add_assistant_message_to_list(messages, response)

        # Execute each tool call
        response["tool_calls"].each do |tool_call|
          execute_tool_call(tool_call, messages)
        end
      end

      def save_tool_call_message(response)
        @history.add_message(
          conversation_id: @conversation_id,
          exchange_id: @exchange_id,
          actor: "orchestrator",
          role: "assistant",
          content: response["content"],
          model: response["model"],
          tokens_input: response["tokens"]["input"] || 0,
          tokens_output: response["tokens"]["output"] || 0,
          spend: response["spend"] || 0.0,
          tool_calls: response["tool_calls"],
          redacted: true
        )
      end

      def display_tool_call_message(response)
        @formatter.display_message_created(
          actor: "orchestrator",
          role: "assistant",
          content: response["content"],
          tool_calls: response["tool_calls"],
          redacted: true
        )
      end

      def display_content_if_present(content)
        return unless content && !content.strip.empty?

        @console.hide_spinner
        @application.send(:output_line, content)
        @console.show_spinner("Thinking...")
      end

      def add_assistant_message_to_list(messages, response)
        messages << {
          "role" => "assistant",
          "content" => response["content"],
          "tool_calls" => response["tool_calls"]
        }
      end

      def execute_tool_call(tool_call, messages)
        result = execute_tool(tool_call)
        tool_result_data = build_tool_result_data(tool_call, result)

        save_tool_result_message(tool_call, tool_result_data)
        display_tool_result_message(tool_result_data)
        add_tool_result_to_messages(messages, tool_call, result)
      end

      def execute_tool(tool_call)
        @tool_registry.execute(
          name: tool_call["name"],
          arguments: tool_call["arguments"],
          history: @history,
          context: {
            "conversation_id" => @conversation_id,
            "model" => @client.model,
            "application" => @application
          }
        )
      end

      def build_tool_result_data(tool_call, result)
        {
          "name" => tool_call["name"],
          "result" => result
        }
      end

      def save_tool_result_message(tool_call, tool_result_data)
        @history.add_message(
          conversation_id: @conversation_id,
          exchange_id: @exchange_id,
          actor: "orchestrator",
          role: "tool",
          content: "",
          tool_call_id: tool_call["id"],
          tool_result: tool_result_data,
          redacted: true
        )
      end

      def display_tool_result_message(tool_result_data)
        @formatter.display_message_created(
          actor: "orchestrator",
          role: "tool",
          tool_result: tool_result_data,
          redacted: true
        )
      end

      def add_tool_result_to_messages(messages, tool_call, result)
        messages << {
          "role" => "tool",
          "tool_call_id" => tool_call["id"],
          "content" => result.is_a?(Hash) ? result.to_json : result.to_s,
          "tool_result" => {
            "name" => tool_call["name"],
            "result" => result
          }
        }
      end
    end
  end
end
