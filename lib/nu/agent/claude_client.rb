# frozen_string_literal: true

require 'anthropic'

module Nu
  module Agent
    class ClaudeClient
      def initialize
        load_api_key
        @client = Anthropic::Client.new(access_token: @api_key.value)
      end

      def chat(prompt:)
        response = @client.messages(
          parameters: {
            model: "claude-sonnet-4-20250514",
            messages: [{ role: "user", content: prompt }],
            max_tokens: 1024
          }
        )

        response.dig("content", 0, "text")
      end

      private

      def load_api_key
        api_key_path = File.join(Dir.home, '.secrets', 'ANTHROPIC_API_KEY')

        if File.exist?(api_key_path)
          key_content = File.read(api_key_path).strip
          @api_key = ApiKey.new(key_content)
        else
          raise Error, "API key not found at #{api_key_path}"
        end
      rescue => e
        raise Error, "Error loading API key: #{e.message}"
      end
    end
  end
end
