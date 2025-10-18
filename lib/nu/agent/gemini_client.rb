# frozen_string_literal: true

module Nu
  module Agent
    class GeminiClient
      extend Forwardable

      attr_reader :token_tracker

      def_delegator :token_tracker, :total_input_tokens, :input_tokens
      def_delegator :token_tracker, :total_output_tokens, :output_tokens
      def_delegator :token_tracker, :total_tokens

      def initialize
        load_api_key
        @client = Gemini.new(
          credentials: {
            service: 'generative-language-api',
            api_key: @api_key.value
          },
          options: { model: model, server_sent_events: true }
        )
        @token_tracker = TokenTracker.new
      end

      def chat(prompt:)
        result = @client.generate_content({
          contents: { role: 'user', parts: { text: prompt } }
        })

        token_tracker.track(
          result.dig('usageMetadata', 'promptTokenCount'),
          result.dig('usageMetadata', 'candidatesTokenCount')
        )

        result.dig('candidates', 0, 'content', 'parts', 0, 'text')
      end

      def name
        "Gemini"
      end

      def model
        'gemini-2.5-flash'
      end

      private

      def load_api_key
        api_key_path = File.join(Dir.home, '.secrets', 'GEMINI_API_KEY')

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
