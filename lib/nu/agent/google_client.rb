# frozen_string_literal: true

require 'securerandom'

module Nu
  module Agent
    class GoogleClient
      SYSTEM_PROMPT = <<~PROMPT
        You are a helpful AI assistant.
        Today is #{Time.now.strftime('%Y-%m-%d')}.

        If you can determine the answer to a question on your own using `bash` do that instead of asking.
      PROMPT

      def initialize(api_key: nil)
        load_api_key(api_key)
        @client = Gemini.new(
          credentials: {
            service: 'generative-language-api',
            api_key: @api_key.value,
            version: 'v1beta'
          },
          options: { model: model, server_sent_events: true }
        )
      end

      def send_message(messages:, system_prompt: SYSTEM_PROMPT, tools: nil)
        formatted_messages = format_messages(messages, system_prompt: system_prompt)

        request = { contents: formatted_messages }
        request[:tools] = [{ 'functionDeclarations' => tools }] if tools && !tools.empty?

        result = @client.generate_content(request)

        # Extract content and tool calls
        parts = result.dig('candidates', 0, 'content', 'parts') || []
        text_content = parts.find { |p| p['text'] }&.dig('text')
        tool_calls = parts.select { |p| p['functionCall'] }.map do |fc|
          {
            'id' => SecureRandom.uuid, # Gemini doesn't provide IDs, generate one
            'name' => fc['functionCall']['name'],
            'arguments' => fc['functionCall']['args']
          }
        end

        {
          'content' => text_content,
          'tool_calls' => tool_calls.empty? ? nil : tool_calls,
          'model' => model,
          'tokens' => {
            'input' => result.dig('usageMetadata', 'promptTokenCount'),
            'output' => result.dig('usageMetadata', 'candidatesTokenCount')
          },
          'finish_reason' => result.dig('candidates', 0, 'finishReason')
        }
      end

      def name
        "Google"
      end

      def model
        'gemini-2.0-flash-exp'
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
        # Internal: { 'actor' => '...', 'role' => 'user'|'assistant', 'content' => '...', 'tool_calls' => [...], 'tool_result' => {...} }
        # Gemini: { role: 'user'|'model'|'function', parts: { text: '...' } or { functionCall/functionResponse: {...} } }

        # Gemini doesn't have a separate system parameter, so we prepend the system prompt
        # as the first user message
        formatted = []

        if system_prompt && !system_prompt.empty?
          formatted << { role: 'user', parts: { text: system_prompt } }
        end

        messages.each do |msg|
          # Handle tool result messages
          if msg['tool_result']
            formatted << {
              role: 'function',
              parts: {
                functionResponse: {
                  name: msg['tool_result']['name'],
                  response: msg['tool_result']['result']
                }
              }
            }
          # Handle messages with tool calls
          elsif msg['tool_calls']
            # Build parts array with text and functionCall
            parts = []
            parts << { text: msg['content'] } if msg['content'] && !msg['content'].empty?
            msg['tool_calls'].each do |tc|
              parts << {
                functionCall: {
                  name: tc['name'],
                  args: tc['arguments']
                }
              }
            end
            formatted << {
              role: 'model',
              parts: parts
            }
          # Regular text message
          else
            formatted << {
              role: msg['role'] == 'assistant' ? 'model' : msg['role'],
              parts: { text: msg['content'] }
            }
          end
        end

        formatted
      end
    end
  end
end
