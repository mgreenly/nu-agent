# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class DatabaseMessage
        def name
          "database_message"
        end

        def description
          "PREFERRED tool for retrieving specific messages by ID from conversation history. " \
            "Use this when you need full details from earlier messages that were redacted to save context space. " \
            "Returns complete message content including role, timestamp, content, tool calls, and results."
        end

        def parameters
          {
            message_id: {
              type: "integer",
              description: "The database ID of the message to retrieve",
              required: true
            }
          }
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
          application = context["application"]

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
          # Format message in a clear, readable way for the LLM
          result = {
            "message_id" => msg["id"],
            "role" => msg["role"],
            "timestamp" => msg["created_at"]
          }

          # Include content if present
          result["message_content"] = msg["content"] if msg["content"] && !msg["content"].empty?

          # Format tool calls in a clear way
          if msg["tool_calls"]
            result["tool_calls"] = msg["tool_calls"].map do |tc|
              {
                "tool_name" => tc["name"],
                "arguments" => tc["arguments"]
              }
            end
          end

          # Format tool results clearly
          if msg["tool_result"]
            result["tool_name"] = msg["tool_result"]["name"]
            result["tool_output"] = msg["tool_result"]["result"]
          end

          # Include errors if present
          result["error_details"] = msg["error"] if msg["error"]

          result
        end
      end
    end
  end
end
