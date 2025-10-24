# frozen_string_literal: true

module Nu
  module Agent
    module Clients
      class Google
        # Explicit imports for external dependencies
        Gemini = ::Gemini
        ApiKey = ::Nu::Agent::ApiKey
        Error = ::Nu::Agent::Error

        SYSTEM_PROMPT = <<~PROMPT
          Today is #{Time.now.strftime('%Y-%m-%d')}.

          Format all responses in raw text, do not use markdown.

          If you can determine the answer to a question on your own using `bash` do that instead of asking.

          Prefer ExecuteRuby/ExecuteBash for one-time script execution over creating temporary files.

          You can use your database tools to access memories from before the current conversation.

          # Pseudonyms
          - "project" can mean "the current directory"
        PROMPT

        # Default model (cheapest option)
        DEFAULT_MODEL = 'gemini-2.5-flash-lite'

        # Model configurations (verified 2025-10-21)
        MODELS = {
          'gemini-2.5-flash-lite' => {
            display_name: 'Gemini 2.5 Flash Lite',
            max_context: 1_048_576,
            pricing: { input: 0.10, output: 0.40 }
          },
          'gemini-2.5-flash' => {
            display_name: 'Gemini 2.5 Flash',
            max_context: 1_048_576,
            pricing: { input: 0.30, output: 2.50 }
          },
          'gemini-2.5-pro' => {
            display_name: 'Gemini 2.5 Pro',
            max_context: 1_048_576,
            pricing: { input: 1.25, output: 10.00 }
          }
        }.freeze

        def initialize(api_key: nil, model: nil)
          load_api_key(api_key)
          @model = model || 'gemini-2.5-flash'
          @client = Gemini.new(
            credentials: {
              service: 'generative-language-api',
              api_key: @api_key.value,
              version: 'v1beta'
            },
            options: { model: @model, server_sent_events: false }
          )
        end

      def send_message(messages:, system_prompt: SYSTEM_PROMPT, tools: nil)
        formatted_messages = format_messages(messages, system_prompt: system_prompt)

        request = { contents: formatted_messages }
        request[:tools] = [{ 'functionDeclarations' => tools }] if tools && !tools.empty?

        begin
          result = @client.generate_content(request)
        rescue Faraday::Error => e
          return format_error_response(e)
        end

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

        input_tokens = result.dig('usageMetadata', 'promptTokenCount')
        output_tokens = result.dig('usageMetadata', 'candidatesTokenCount')

        {
          'content' => text_content,
          'tool_calls' => tool_calls.empty? ? nil : tool_calls,
          'model' => model,
          'tokens' => {
            'input' => input_tokens,
            'output' => output_tokens
          },
          'spend' => calculate_cost(input_tokens: input_tokens, output_tokens: output_tokens),
          'finish_reason' => result.dig('candidates', 0, 'finishReason')
        }
      end

      def name
        "Google"
      end

      def model
        @model
      end

      def max_context
        MODELS.dig(@model, :max_context) || MODELS.dig('gemini-2.5-flash', :max_context)
      end

      def format_tools(tool_registry)
        tool_registry.for_google
      end

      def list_models
        {
          provider: "Google",
          models: MODELS.map { |id, info| { id: id, display_name: info[:display_name] } }
        }
      end

      def calculate_cost(input_tokens:, output_tokens:)
        return 0.0 if input_tokens.nil? || output_tokens.nil?

        pricing = MODELS.dig(@model, :pricing) || MODELS.dig('gemini-2.5-flash', :pricing)
        input_cost = (input_tokens / 1_000_000.0) * pricing[:input]
        output_cost = (output_tokens / 1_000_000.0) * pricing[:output]
        input_cost + output_cost
      end

      private

        def format_error_response(error)
          status = error.response&.dig(:status) || 'unknown'
          headers = error.response&.dig(:headers) || {}

          # Try multiple ways to get the body
          body = error.response&.dig(:body) ||
                 error.response_body ||
                 error.response&.[](:body) ||
                 error.message

          {
            'error' => {
              'status' => status,
              'headers' => headers.to_h,
              'body' => body,
              'raw_error' => error.inspect  # Add for debugging
            },
            'content' => "API Error: #{status}",
            'model' => @model
          }
        end

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
        # Internal: { 'actor' => '...', 'role' => 'user'|'assistant'|'tool', 'content' => '...', 'tool_calls' => [...], 'tool_result' => {...} }
        # Gemini: { role: 'user'|'model'|'function', parts: { text: '...' } or { functionCall/functionResponse: {...} } }

        # Gemini doesn't have a separate system parameter, so we prepend the system prompt
        # as the first user message
        formatted = []

        if system_prompt && !system_prompt.empty?
          formatted << { role: 'user', parts: [{ text: system_prompt }] }
        end

        messages.each do |msg|
          # Handle tool result messages
          if msg['tool_result']
            formatted << {
              role: 'function',
              parts: [{
                functionResponse: {
                  name: msg['tool_result']['name'],
                  response: msg['tool_result']['result']
                }
              }]
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
            # Translate our domain model to Gemini's format
            # Our 'assistant' becomes 'model', 'tool' becomes 'function'
            role = case msg['role']
                   when 'assistant' then 'model'
                   when 'tool' then 'function'
                   else msg['role']
                   end
            formatted << {
              role: role,
              parts: [{ text: msg['content'] }]
            }
          end
        end

        formatted
      end
    end
  end
  end
end
