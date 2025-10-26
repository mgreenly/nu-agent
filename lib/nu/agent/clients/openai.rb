# frozen_string_literal: true

module Nu
  module Agent
    module Clients
      class OpenAI
        # Explicit imports for external dependencies
        OpenAIGem = ::OpenAI
        ApiKey = ::Nu::Agent::ApiKey
        Error = ::Nu::Agent::Error

        SYSTEM_PROMPT = <<~PROMPT.freeze
          Today is #{Time.now.strftime('%Y-%m-%d')}.

          Format all responses in raw text, do not use markdown.

          If you can determine the answer to a question on your own, use your tools to find it instead of asking.

          Use execute_bash for shell commands and execute_python for Python scripts.

          These are your only tools to execute processes on the host.

          You can use your database tools to access memories from before the current conversation.

          You can use your tools to write scripts and you have access to the internet.

          # Pseudonyms
          - "project" can mean "the current directory"
        PROMPT

        # Default model (good balance of cost and quality)
        DEFAULT_MODEL = "gpt-5-mini"

        # Model configurations (verified 2025-10-21)
        MODELS = {
          "gpt-5-nano-2025-08-07" => {
            display_name: "GPT-5 Nano",
            max_context: 400_000,
            pricing: { input: 0.05, output: 0.40 }
          },
          "gpt-5-mini" => {
            display_name: "GPT-5 Mini",
            max_context: 400_000,
            pricing: { input: 0.25, output: 2.00 }
          },
          "gpt-5" => {
            display_name: "GPT-5",
            max_context: 400_000,
            pricing: { input: 1.25, output: 10.00 }
          }
        }.freeze

        # Rate limiting for embeddings API
        EMBEDDING_RATE_LIMIT = {
          requests_per_minute: 10,
          batch_size: 10
        }.freeze

        # Embedding model pricing (per 1M tokens)
        EMBEDDING_PRICING = {
          "text-embedding-3-small" => 0.020
        }.freeze

        def initialize(api_key: nil, model: nil)
          load_api_key(api_key)
          @model = model || "gpt-5"
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
          message = response.dig("choices", 0, "message") || {}
          text_content = message["content"]
          tool_calls = message["tool_calls"]&.map do |tc|
            {
              "id" => tc["id"],
              "name" => tc.dig("function", "name"),
              "arguments" => JSON.parse(tc.dig("function", "arguments"))
            }
          end

          input_tokens = response.dig("usage", "prompt_tokens")
          output_tokens = response.dig("usage", "completion_tokens")

          {
            "content" => text_content,
            "tool_calls" => tool_calls&.empty? ? nil : tool_calls,
            "model" => model,
            "tokens" => {
              "input" => input_tokens,
              "output" => output_tokens
            },
            "spend" => calculate_cost(input_tokens: input_tokens, output_tokens: output_tokens),
            "finish_reason" => response.dig("choices", 0, "finish_reason")
          }
        end

        # Generate embeddings for text input
        # @param text [String, Array<String>] Single text or array of texts to embed
        # @param model [String] Embedding model to use (default: text-embedding-3-small)
        # @return [Hash] Response with embeddings, tokens, and cost
        def generate_embedding(text, model: "text-embedding-3-small")
          input = text.is_a?(Array) ? text : [text]

          begin
            response = @client.embeddings(
              parameters: {
                model: model,
                input: input
              }
            )
          rescue Faraday::Error => e
            return format_error_response(e)
          end

          # Extract embeddings
          embeddings = response["data"].map { |d| d["embedding"] }

          # Get usage information
          total_tokens = response.dig("usage", "total_tokens") || 0

          # Calculate cost
          pricing = EMBEDDING_PRICING[model] || 0.020
          cost = (total_tokens / 1_000_000.0) * pricing

          {
            "embeddings" => text.is_a?(Array) ? embeddings : embeddings.first,
            "model" => model,
            "tokens" => total_tokens,
            "spend" => cost
          }
        end

        def name
          "OpenAI"
        end

        attr_reader :model

        def max_context
          MODELS.dig(@model, :max_context) || MODELS.dig("gpt-5", :max_context)
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

          pricing = MODELS.dig(@model, :pricing) || MODELS.dig("gpt-5", :pricing)
          input_cost = (input_tokens / 1_000_000.0) * pricing[:input]
          output_cost = (output_tokens / 1_000_000.0) * pricing[:output]
          input_cost + output_cost
        end

        private

        def format_error_response(error)
          status = error.response&.dig(:status) || "unknown"
          headers = error.response&.dig(:headers) || {}

          # Try multiple ways to get the body
          body = error.response&.dig(:body) ||
                 error.response_body ||
                 error.response&.[](:body) ||
                 error.message

          {
            "error" => {
              "status" => status,
              "headers" => headers.to_h,
              "body" => body,
              "raw_error" => error.inspect # Add for debugging
            },
            "content" => "API Error: #{status}",
            "model" => @model
          }
        end

        def load_api_key(provided_key)
          if provided_key
            @api_key = ApiKey.new(provided_key)
          else
            api_key_path = File.join(Dir.home, ".secrets", "OPENAI_API_KEY")

            raise Error, "API key not found at #{api_key_path}" unless File.exist?(api_key_path)

            key_content = File.read(api_key_path).strip
            @api_key = ApiKey.new(key_content)

          end
        rescue StandardError => e
          raise Error, "Error loading API key: #{e.message}"
        end

        def format_messages(messages, system_prompt:)
          # Convert from internal format to OpenAI format
          # Internal: { 'actor' => '...', 'role' => 'user'|'assistant'|'tool',
          #             'content' => '...', 'tool_calls' => [...], 'tool_result' => {...} }
          # OpenAI: { role: 'system'|'user'|'assistant'|'tool', content: '...' }
          # Note: Our 'tool' role maps directly to OpenAI's 'tool' role

          formatted = []

          # OpenAI uses a system message at the beginning
          formatted << { role: "system", content: system_prompt } if system_prompt && !system_prompt.empty?

          messages.each do |msg|
            # Handle tool result messages
            if msg["tool_result"]
              formatted << {
                role: "tool",
                tool_call_id: msg["tool_call_id"],
                content: JSON.generate(msg["tool_result"]["result"])
              }
            # Handle messages with tool calls
            elsif msg["tool_calls"]
              # Build message with text and tool_calls
              formatted_msg = { role: "assistant" }
              formatted_msg[:content] = msg["content"] if msg["content"] && !msg["content"].empty?
              formatted_msg[:tool_calls] = msg["tool_calls"].map do |tc|
                {
                  id: tc["id"],
                  type: "function",
                  function: {
                    name: tc["name"],
                    arguments: JSON.generate(tc["arguments"])
                  }
                }
              end
              formatted << formatted_msg
            # Regular text message
            else
              formatted << {
                role: msg["role"],
                content: msg["content"]
              }
            end
          end

          formatted
        end
      end
    end
  end
end
