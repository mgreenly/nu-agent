# frozen_string_literal: true

require 'gemini-ai'

module Nu
  module Agent
    class GeminiClient
      def initialize
        load_api_key
        # Available models for Generative Language API (as of Oct 2025):
        # - gemini-2.5-flash: Fast, efficient model
        # - gemini-2.0-flash-001: Optimized for cost efficiency
        # - gemini-flash-latest: Points to latest Flash release
        # - gemini-2.5-pro: More capable model
        @client = Gemini.new(
          credentials: {
            service: 'generative-language-api',
            api_key: @api_key.value
          },
          options: { model: 'gemini-2.0-flash-001', server_sent_events: true }
        )
        @token_tracker = TokenTracker.new
      end

      def chat(prompt:)
        result = @client.generate_content({
          contents: { role: 'user', parts: { text: prompt } }
        })

        # Track token usage internally
        # Gemini returns: { 'usageMetadata' => { 'promptTokenCount' => X, 'candidatesTokenCount' => Y, 'totalTokenCount' => Z } }
        # Convert to our format: { 'input_tokens' => X, 'output_tokens' => Y }
        if result['usageMetadata']
          usage = {
            'input_tokens' => result['usageMetadata']['promptTokenCount'] || 0,
            'output_tokens' => result['usageMetadata']['candidatesTokenCount'] || 0
          }
          @token_tracker.track(usage)
        end

        # Return only the text (same interface as ClaudeClient)
        result.dig('candidates', 0, 'content', 'parts', 0, 'text')
      end

      # Token tracking methods
      def input_tokens
        @token_tracker.total_input_tokens
      end

      def output_tokens
        @token_tracker.total_output_tokens
      end

      def total_tokens
        @token_tracker.total_tokens
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
