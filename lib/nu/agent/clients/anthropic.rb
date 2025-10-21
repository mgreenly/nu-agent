# frozen_string_literal: true

module Nu
  module Agent
    module Clients
      class Anthropic
        AnthropicGem = ::Anthropic
        ApiKey = ::Nu::Agent::ApiKey
        Error = ::Nu::Agent::Error

        SYSTEM_PROMPT = <<~PROMPT
          You are a helpful AI assistant.
          Today is #{Time.now.strftime('%Y-%m-%d')}.

          If you can determine the answer to a question on your own using `bash` do that instead of asking.
        PROMPT

        def initialize(api_key: nil)
          load_api_key(api_key)
          @client = AnthropicGem::Client.new(access_token: @api_key.value)
        end

      def send_message(messages:, system_prompt: SYSTEM_PROMPT, tools: nil)
        formatted_messages = format_messages(messages)

        parameters = {
          model: model,
          system: system_prompt,
          messages: formatted_messages,
          max_tokens: 4096
        }

        parameters[:tools] = tools if tools && !tools.empty?

        response = @client.messages(parameters: parameters)

        # Extract content (text and/or tool calls)
        content_blocks = response.dig("content") || []
        text_content = content_blocks.find { |b| b["type"] == "text" }&.dig("text")
        tool_calls = content_blocks.select { |b| b["type"] == "tool_use" }.map do |tc|
          {
            "id" => tc["id"],
            "name" => tc["name"],
            "arguments" => tc["input"]
          }
        end

        {
          "content" => text_content,
          "tool_calls" => tool_calls.empty? ? nil : tool_calls,
          "model" => model,
          "tokens" => {
            "input" => response.dig("usage", "input_tokens"),
            "output" => response.dig("usage", "output_tokens")
          },
          "finish_reason" => response.dig("stop_reason")
        }
      end

      def name
        "Anthropic"
      end

      def model
        # "claude-sonnet-4-20250514"
        "claude-sonnet-4-5-20250929"
      end

      private

        def load_api_key(provided_key)
          if provided_key
            @api_key = ApiKey.new(provided_key)
          else
            api_key_path = File.join(Dir.home, '.secrets', 'ANTHROPIC_API_KEY')

            if File.exist?(api_key_path)
              key_content = File.read(api_key_path).strip
              @api_key = ApiKey.new(key_content)
            else
              raise Error, "API key not found at #{api_key_path}"
            end
          end
        rescue => e
          raise Error, "Error loading API key: #{e.message}"
        end

      def format_messages(messages)
        # Convert from internal format to Anthropic format
        # Internal: { "actor" => '...', "role" => 'user'|'assistant', "content" => '...', "tool_calls" => [...], "tool_result" => {...} }
        # Anthropic: { role: 'user'|'assistant', content: '...' or [...] }
        messages.map do |msg|
          formatted = { role: msg["role"] }

          # Handle tool result messages
          if msg["tool_result"]
            formatted[:content] = [
              {
                type: 'tool_result',
                tool_use_id: msg["tool_call_id"],
                content: JSON.generate(msg["tool_result"]["result"])
              }
            ]
          # Handle messages with tool calls
          elsif msg["tool_calls"]
            # Build content array with text and tool_use blocks
            content = []
            content << { type: 'text', text: msg["content"] } if msg["content"] && !msg["content"].empty?
            msg["tool_calls"].each do |tc|
              content << {
                type: 'tool_use',
                id: tc["id"],
                name: tc["name"],
                input: tc["arguments"]
              }
            end
            formatted[:content] = content
          # Regular text message
          else
            formatted[:content] = msg["content"]
          end

          formatted
        end
      end
    end
  end
  end
end
