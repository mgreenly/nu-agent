# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DatabaseMessage
        PARAMETERS = {
          message_id: {
            type: "integer",
            description: "The database ID of the message to retrieve",
            required: true
          }
        }.freeze

        def name
          "database_message"
        end

        def description
          "PREFERRED tool for retrieving specific messages by ID from conversation history. " \
            "Use this when you need full details from earlier messages that were redacted to save context space. " \
            "Returns complete message content including role, timestamp, content, tool calls, and results."
        end

        def parameters
          PARAMETERS
        end

        def operation_type
          :read
        end

        def scope
          :unconfined
        end

        def execute(arguments:, history:, context:)
          message_id = arguments[:message_id] || arguments["message_id"]

          if message_id.nil?
            return {
              error: "message_id is required"
            }
          end

          conversation_id = context["conversation_id"]

          # Debug output
          context["application"]

          begin
            message = history.get_message_by_id(message_id, conversation_id: conversation_id)

            if message
              format_message(message)
            else
              {
                error: "Message not found or not accessible",
                message_id: message_id
              }
            end
          rescue StandardError => e
            {
              error: "Failed to retrieve message: #{e.message}",
              message_id: message_id
            }
          end
        end

        private

        def format_message(msg)
          result = build_base_result(msg)
          add_optional_fields(result, msg)
          result
        end

        def build_base_result(msg)
          {
            "message_id" => msg["id"],
            "role" => msg["role"],
            "timestamp" => msg["created_at"]
          }
        end

        def add_optional_fields(result, msg)
          result["message_content"] = msg["content"] if msg["content"] && !msg["content"].empty?
          result["tool_calls"] = format_tool_calls(msg["tool_calls"]) if msg["tool_calls"]
          add_tool_result(result, msg["tool_result"]) if msg["tool_result"]
          result["error_details"] = msg["error"] if msg["error"]
        end

        def format_tool_calls(tool_calls)
          tool_calls.map do |tc|
            {
              "tool_name" => tc["name"],
              "arguments" => tc["arguments"]
            }
          end
        end

        def add_tool_result(result, tool_result)
          result["tool_name"] = tool_result["name"]
          result["tool_output"] = tool_result["result"]
        end
      end
    end
  end
end
