# frozen_string_literal: true

module Nu
  module Agent
    class GoogleClient
      SYSTEM_PROMPT = <<~PROMPT
        You are a helpful AI assistant.
        Today is #{Time.now.strftime('%Y-%m-%d')}.
      PROMPT

      def initialize(api_key: nil)
        load_api_key(api_key)
        @client = Gemini.new(
          credentials: {
            service: 'generative-language-api',
            api_key: @api_key.value
          },
          options: { model: model, server_sent_events: true }
        )
      end

      def send_message(messages:, system_prompt: SYSTEM_PROMPT)
        formatted_messages = format_messages(messages, system_prompt: system_prompt)

        result = @client.generate_content({
          contents: formatted_messages
        })

        {
          content: result.dig('candidates', 0, 'content', 'parts', 0, 'text'),
          model: model,
          tokens: {
            input: result.dig('usageMetadata', 'promptTokenCount'),
            output: result.dig('usageMetadata', 'candidatesTokenCount')
          },
          finish_reason: result.dig('candidates', 0, 'finishReason')
        }
      end

      def name
        "Google"
      end

      def model
        'gemini-2.5-flash'
      end

      private

      def load_api_key(provided_key)
        if provided_key
          @api_key = ApiKey.new(provided_key)
        else
          api_key_path = File.join(Dir.home, '.secrets', 'GEMINI_API_KEY')

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

      def format_messages(messages, system_prompt:)
        # Convert from internal format to Gemini format
        # Internal: { actor: '...', role: 'user'|'assistant', content: '...' }
        # Gemini: { role: 'user'|'model', parts: { text: '...' } }

        # Gemini doesn't have a separate system parameter, so we prepend the system prompt
        # as the first user message
        formatted = []

        if system_prompt && !system_prompt.empty?
          formatted << { role: 'user', parts: { text: system_prompt } }
        end

        messages.each do |msg|
          formatted << {
            role: msg[:role] == 'assistant' ? 'model' : msg[:role],
            parts: { text: msg[:content] }
          }
        end

        formatted
      end
    end
  end
end
