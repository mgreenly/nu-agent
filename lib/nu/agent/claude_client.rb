# frozen_string_literal: true

module Nu
  module Agent
    class ClaudeClient
      extend Forwardable

      attr_reader :token_tracker

      def_delegator :token_tracker, :total_input_tokens, :input_tokens
      def_delegator :token_tracker, :total_output_tokens, :output_tokens
      def_delegator :token_tracker, :total_tokens

      def initialize
        load_api_key
        @client = Anthropic::Client.new(access_token: @api_key.value)
        @token_tracker = TokenTracker.new
      end

      def chat(prompt:)
        response = @client.messages(
          parameters: {
            model: model,
            messages: [{ role: "user", content: prompt }],
            max_tokens: 1024
          }
        )

        token_tracker.track(
          response.dig("usage", "input_tokens"),
          response.dig("usage", "output_tokens")
        )

        response.dig("content", 0, "text")
      end

      def response(prompt)
        text = chat(prompt: prompt)
        "\n#{text}\n\nTokens: #{input_tokens} in / #{output_tokens} out / #{total_tokens} total"
      end

      def name
        "Claude"
      end

      def model
        "claude-sonnet-4-20250514"
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
