# frozen_string_literal: true

module Nu
  module Agent
    module Clients
      class Anthropic
        AnthropicGem = ::Anthropic
        ApiKey = ::Nu::Agent::ApiKey
        Error = ::Nu::Agent::Error

        SYSTEM_PROMPT = <<~PROMPT
          You are a helpful AI assistant.
          Today is #{Time.now.strftime('%Y-%m-%d')}.

          If you can determine the answer to a question on your own using `bash` do that instead of asking.
        PROMPT

        # Pricing per million tokens (verified 2025-10-21)
        PRICING = {
          'claude-sonnet-4-5-20250929' => { input: 3.00, output: 15.00 },
          'claude-haiku-4-5-20251001' => { input: 1.00, output: 5.00 },
          'claude-opus-4-1-20250805' => { input: 15.00, output: 75.00 }
        }.freeze

        # Max context window in tokens (verified 2025-10-21)
        MAX_CONTEXT = {
          'claude-sonnet-4-5-20250929' => 200_000,
          'claude-haiku-4-5-20251001' => 200_000,
          'claude-opus-4-1-20250805' => 200_000
        }.freeze

        def initialize(api_key: nil, model: nil)
          load_api_key(api_key)
          @model = model || 'claude-sonnet-4-5-20250929'
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

        response = @client.messages(parameters: parameters)

        # Extract content (text and/or tool calls)
        content_blocks = response.dig("content") || []
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
          "finish_reason" => response.dig("stop_reason")
        }
      end

      def name
        "Anthropic"
      end

      def model
        @model
      end

      def max_context
        MAX_CONTEXT[@model] || MAX_CONTEXT['claude-sonnet-4-5-20250929']
      end

      def format_tools(tool_registry)
        tool_registry.for_anthropic
      end

      def list_models
        begin
          # Use the anthropic gem's underlying connection to call the models endpoint
          response = @client.connection.get('v1/models')
          models_data = JSON.parse(response.body)
          models = models_data['data'] || []

          {
            provider: "Anthropic",
            note: "Live list from Anthropic API",
            models: models.map { |m| { id: m['id'], name: m['name'], display_name: m['display_name'] } }
          }
        rescue => e
          {
            provider: "Anthropic",
            error: "Failed to fetch models: #{e.message}",
            note: "Falling back to curated list",
            models: [
              { id: "claude-sonnet-4-5-20250929", aliases: ["sonnet", "claude-sonnet-4-5"] },
              { id: "claude-haiku-4-5-20251001", aliases: ["haiku", "claude-haiku-4-5"] },
              { id: "claude-opus-4-1-20250805", aliases: ["opus", "claude-opus-4-1"] }
            ]
          }
        end
      end

      def calculate_cost(input_tokens:, output_tokens:)
        return 0.0 if input_tokens.nil? || output_tokens.nil?

        pricing = PRICING[@model] || PRICING['claude-sonnet-4-5-20250929']
        input_cost = (input_tokens / 1_000_000.0) * pricing[:input]
        output_cost = (output_tokens / 1_000_000.0) * pricing[:output]
        input_cost + output_cost
      end

      private

        def load_api_key(provided_key)
          if provided_key
            @api_key = ApiKey.new(provided_key)
          else
            api_key_path = File.join(Dir.home, '.secrets', 'ANTHROPIC_API_KEY')

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

      def format_messages(messages)
        # Convert from internal format to Anthropic format
        # Internal: { "actor" => '...', "role" => 'user'|'assistant'|'tool', "content" => '...', "tool_calls" => [...], "tool_result" => {...} }
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
                type: 'tool_result',
                tool_use_id: msg["tool_call_id"],
                content: JSON.generate(msg["tool_result"]["result"])
              }
            ]
          # Handle messages with tool calls
          elsif msg["tool_calls"]
            # Build content array with text and tool_use blocks
            content = []
            content << { type: 'text', text: msg["content"] } if msg["content"] && !msg["content"].empty?
            msg["tool_calls"].each do |tc|
              content << {
                type: 'tool_use',
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
