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
      end

      def chat(prompt:)
        result = @client.generate_content({
          contents: { role: 'user', parts: { text: prompt } }
        })

        result.dig('candidates', 0, 'content', 'parts', 0, 'text')
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
