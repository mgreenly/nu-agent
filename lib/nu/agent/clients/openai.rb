# frozen_string_literal: true

module Nu
  module Agent
    module Clients
      class OpenAI
        # Explicit imports for external dependencies
        OpenAIGem = ::OpenAI
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

        # Default model (good balance of cost and quality)
        DEFAULT_MODEL = 'gpt-5-mini'

        # Model configurations (verified 2025-10-21)
        MODELS = {
          'gpt-5-nano-2025-08-07' => {
            display_name: 'GPT-5 Nano',
            max_context: 400_000,
            pricing: { input: 0.05, output: 0.40 }
          },
          'gpt-5-mini' => {
            display_name: 'GPT-5 Mini',
            max_context: 400_000,
            pricing: { input: 0.25, output: 2.00 }
          },
          'gpt-5' => {
            display_name: 'GPT-5',
            max_context: 400_000,
            pricing: { input: 1.25, output: 10.00 }
          }
        }.freeze

        def initialize(api_key: nil, model: nil)
          load_api_key(api_key)
          @model = model || 'gpt-5'
          @client = OpenAIGem::Client.new(access_token: @api_key.value)
        end

        def send_message(messages:, system_prompt: SYSTEM_PROMPT, tools: nil)
          formatted_messages = format_messages(messages, system_prompt: system_prompt)

          parameters = {
            model: model,
            messages: formatted_messages
          }

          parameters[:tools] = tools if tools && !tools.empty?

          begin
            response = @client.chat(parameters: parameters)
          rescue Faraday::Error => e
            return format_error_response(e)
          end

          # Extract content and tool calls
          message = response.dig('choices', 0, 'message') || {}
          text_content = message['content']
          tool_calls = message['tool_calls']&.map do |tc|
            {
              'id' => tc['id'],
              'name' => tc.dig('function', 'name'),
              'arguments' => JSON.parse(tc.dig('function', 'arguments'))
            }
          end

          input_tokens = response.dig('usage', 'prompt_tokens')
          output_tokens = response.dig('usage', 'completion_tokens')

          {
            'content' => text_content,
            'tool_calls' => tool_calls&.empty? ? nil : tool_calls,
            'model' => model,
            'tokens' => {
              'input' => input_tokens,
              'output' => output_tokens
            },
            'spend' => calculate_cost(input_tokens: input_tokens, output_tokens: output_tokens),
            'finish_reason' => response.dig('choices', 0, 'finish_reason')
          }
        end

        def name
          "OpenAI"
        end

        def model
          @model
        end

        def max_context
          MODELS.dig(@model, :max_context) || MODELS.dig('gpt-5', :max_context)
        end

        def format_tools(tool_registry)
          tool_registry.for_openai
        end

        def list_models
          {
            provider: "OpenAI",
            models: MODELS.map { |id, info| { id: id, display_name: info[:display_name] } }
          }
        end

        def calculate_cost(input_tokens:, output_tokens:)
          return 0.0 if input_tokens.nil? || output_tokens.nil?

          pricing = MODELS.dig(@model, :pricing) || MODELS.dig('gpt-5', :pricing)
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
            api_key_path = File.join(Dir.home, '.secrets', 'OPENAI_API_KEY')

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
          # Convert from internal format to OpenAI format
          # Internal: { 'actor' => '...', 'role' => 'user'|'assistant'|'tool', 'content' => '...', 'tool_calls' => [...], 'tool_result' => {...} }
          # OpenAI: { role: 'system'|'user'|'assistant'|'tool', content: '...' }
          # Note: Our 'tool' role maps directly to OpenAI's 'tool' role

          formatted = []

          # OpenAI uses a system message at the beginning
          if system_prompt && !system_prompt.empty?
            formatted << { role: 'system', content: system_prompt }
          end

          messages.each do |msg|
            # Handle tool result messages
            if msg['tool_result']
              formatted << {
                role: 'tool',
                tool_call_id: msg['tool_call_id'],
                content: JSON.generate(msg['tool_result']['result'])
              }
            # Handle messages with tool calls
            elsif msg['tool_calls']
              # Build message with text and tool_calls
              formatted_msg = { role: 'assistant' }
              formatted_msg[:content] = msg['content'] if msg['content'] && !msg['content'].empty?
              formatted_msg[:tool_calls] = msg['tool_calls'].map do |tc|
                {
                  id: tc['id'],
                  type: 'function',
                  function: {
                    name: tc['name'],
                    arguments: JSON.generate(tc['arguments'])
                  }
                }
              end
              formatted << formatted_msg
            # Regular text message
            else
              formatted << {
                role: msg['role'],
                content: msg['content']
              }
            end
          end

          formatted
        end
      end
    end
  end
end
