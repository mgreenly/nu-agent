# frozen_string_literal: true

module Nu
  module Agent
    module Clients
      class Anthropic
        AnthropicGem = ::Anthropic
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

        # Default model (cheapest option)
        DEFAULT_MODEL = "claude-haiku-4-5"

        # Model configurations (verified 2025-10-21)
        MODELS = {
          "claude-haiku-4-5" => {
            display_name: "Claude Haiku 4.5",
            max_context: 200_000,
            pricing: { input: 1.00, output: 5.00 }
          },
          "claude-sonnet-4-5" => {
            display_name: "Claude Sonnet 4.5",
            max_context: 200_000,
            pricing: { input: 3.00, output: 15.00 }
          },
          "claude-opus-4-1" => {
            display_name: "Claude Opus 4.1",
            max_context: 200_000,
            pricing: { input: 15.00, output: 75.00 }
          }
        }.freeze

        def initialize(api_key: nil, model: nil)
          load_api_key(api_key)
          @model = model || "claude-sonnet-4-5"
          @client = AnthropicGem::Client.new(access_token: @api_key.value)
        end

        def send_message(messages:, system_prompt: SYSTEM_PROMPT, tools: nil)
          formatted_messages = format_messages(messages)

          parameters = {
            model: model,
            system: system_prompt,
            messages: formatted_messages,
            max_tokens: 4096
          }

          parameters[:tools] = tools if tools && !tools.empty?

          begin
            response = @client.messages(parameters: parameters)
          rescue Faraday::Error => e
            return format_error_response(e)
          end

          # Extract content (text and/or tool calls)
          content_blocks = response["content"] || []
          text_content = content_blocks.find { |b| b["type"] == "text" }&.dig("text")
          tool_calls = content_blocks.select { |b| b["type"] == "tool_use" }.map do |tc|
            {
              "id" => tc["id"],
              "name" => tc["name"],
              "arguments" => tc["input"]
            }
          end

          input_tokens = response.dig("usage", "input_tokens")
          output_tokens = response.dig("usage", "output_tokens")

          {
            "content" => text_content,
            "tool_calls" => tool_calls.empty? ? nil : tool_calls,
            "model" => model,
            "tokens" => {
              "input" => input_tokens,
              "output" => output_tokens
            },
            "spend" => calculate_cost(input_tokens: input_tokens, output_tokens: output_tokens),
            "finish_reason" => response["stop_reason"]
          }
        end

        def name
          "Anthropic"
        end

        attr_reader :model

        def max_context
          MODELS.dig(@model, :max_context) || MODELS.dig("claude-sonnet-4-5", :max_context)
        end

        def format_tools(tool_registry)
          tool_registry.for_anthropic
        end

        def list_models
          {
            provider: "Anthropic",
            models: MODELS.map { |id, info| { id: id, display_name: info[:display_name] } }
          }
        end

        def calculate_cost(input_tokens:, output_tokens:)
          return 0.0 if input_tokens.nil? || output_tokens.nil?

          pricing = MODELS.dig(@model, :pricing) || MODELS.dig("claude-sonnet-4-5", :pricing)
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
            api_key_path = File.join(Dir.home, ".secrets", "ANTHROPIC_API_KEY")

            raise Error, "API key not found at #{api_key_path}" unless File.exist?(api_key_path)

            key_content = File.read(api_key_path).strip
            @api_key = ApiKey.new(key_content)

          end
        rescue StandardError => e
          raise Error, "Error loading API key: #{e.message}"
        end

        def format_messages(messages)
          # Convert from internal format to Anthropic format
          # Internal: { "actor" => '...', "role" => 'user'|'assistant'|'tool',
          #             "content" => '...', "tool_calls" => [...], "tool_result" => {...} }
          # Anthropic: { role: 'user'|'assistant', content: '...' or [...] }
          messages.map do |msg|
            # Translate our domain model to Anthropic's format
            # Our 'tool' role becomes 'user' for Anthropic
            role = msg["role"] == "tool" ? "user" : msg["role"]
            formatted = { role: role }

            # Handle tool result messages
            if msg["tool_result"]
              formatted[:content] = [
                {
                  type: "tool_result",
                  tool_use_id: msg["tool_call_id"],
                  content: JSON.generate(msg["tool_result"]["result"])
                }
              ]
            # Handle messages with tool calls
            elsif msg["tool_calls"]
              # Build content array with text and tool_use blocks
              content = []
              content << { type: "text", text: msg["content"] } if msg["content"] && !msg["content"].empty?
              msg["tool_calls"].each do |tc|
                content << {
                  type: "tool_use",
                  id: tc["id"],
                  name: tc["name"],
                  input: tc["arguments"]
                }
              end
              formatted[:content] = content
            # Regular text message
            else
              formatted[:content] = msg["content"]
            end

            formatted
          end
        end
      end
    end
  end
end
