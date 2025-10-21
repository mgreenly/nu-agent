# frozen_string_literal: true

module Nu
  module Agent
    class AnthropicClient
      SYSTEM_PROMPT = <<~PROMPT
        You are a helpful AI assistant.
        Today is #{Time.now.strftime('%Y-%m-%d')}.
      PROMPT

      def initialize(api_key: nil)
        load_api_key(api_key)
        @client = Anthropic::Client.new(access_token: @api_key.value)
      end

      def send_message(messages:, system_prompt: SYSTEM_PROMPT)
        formatted_messages = format_messages(messages)

        response = @client.messages(
          parameters: {
            model: model,
            system: system_prompt,
            messages: formatted_messages,
            max_tokens: 4096
          }
        )

        {
          content: response.dig("content", 0, "text"),
          model: model,
          tokens: {
            input: response.dig("usage", "input_tokens"),
            output: response.dig("usage", "output_tokens")
          },
          finish_reason: response.dig("stop_reason")
        }
      end

      def name
        "Anthropic"
      end

      def model
        "claude-sonnet-4-20250514"
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
        # Internal: { actor: '...', role: 'user'|'assistant', content: '...' }
        # Anthropic: { role: 'user'|'assistant', content: '...' }
        messages.map do |msg|
          {
            role: msg[:role],
            content: msg[:content]
          }
        end
      end
    end
  end
end
