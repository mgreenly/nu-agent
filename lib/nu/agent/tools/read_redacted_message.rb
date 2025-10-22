# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class ReadRedactedMessage
        def name
          "read_redacted_message"
        end

        def description
          "Retrieve the full content of a redacted message from the history database by its ID. Use this when you need specific details from earlier in the conversation that were redacted to save context space."
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

          raise ArgumentError, "message_id is required" if message_id.nil?

          conversation_id = context['conversation_id']

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
          rescue => e
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
            'message_id' => msg['id'],
            'role' => msg['role'],
            'timestamp' => msg['created_at']
          }

          # Include content if present
          if msg['content'] && !msg['content'].empty?
            result['message_content'] = msg['content']
          end

          # Format tool calls in a clear way
          if msg['tool_calls']
            result['tool_calls'] = msg['tool_calls'].map do |tc|
              {
                'tool_name' => tc['name'],
                'arguments' => tc['arguments']
              }
            end
          end

          # Format tool results clearly
          if msg['tool_result']
            result['tool_name'] = msg['tool_result']['name']
            result['tool_output'] = msg['tool_result']['result']
          end

          # Include errors if present
          if msg['error']
            result['error_details'] = msg['error']
          end

          result
        end
      end
    end
  end
end
