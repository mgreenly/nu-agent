# frozen_string_literal: true

module Nu
  module Agent
    module Clients
      class XAI < OpenAI
        # Explicit imports for external dependencies
        ApiKey = ::Nu::Agent::ApiKey
        Error = ::Nu::Agent::Error

        # Pricing per million tokens (verified 2025-10-21)
        PRICING = {
          'grok-3' => { input: 3.00, output: 15.00 },
          'grok-code-fast-1' => { input: 0.20, output: 1.50 }
        }.freeze

        # Max context window in tokens (verified 2025-10-21)
        MAX_CONTEXT = {
          'grok-3' => 1_000_000,
          'grok-code-fast-1' => 256_000
        }.freeze

        def initialize(api_key: nil, model: nil)
          load_api_key(api_key)
          @model = model || 'grok-3'
          @client = OpenAIGem::Client.new(
            access_token: @api_key.value,
            uri_base: 'https://api.x.ai/v1'
          )
        end

        def name
          "X.AI"
        end

        def list_models
          {
            provider: "X.AI",
            note: "X.AI Grok models",
            models: [
              { id: "grok-3", aliases: ["grok"] },
              { id: "grok-code-fast-1" }
            ]
          }
        end

        def max_context
          MAX_CONTEXT[@model] || MAX_CONTEXT['grok-3']
        end

        def calculate_cost(input_tokens:, output_tokens:)
          return 0.0 if input_tokens.nil? || output_tokens.nil?

          pricing = PRICING[@model] || PRICING['grok-beta']
          input_cost = (input_tokens / 1_000_000.0) * pricing[:input]
          output_cost = (output_tokens / 1_000_000.0) * pricing[:output]
          input_cost + output_cost
        end

        private

        def load_api_key(provided_key)
          if provided_key
            @api_key = ApiKey.new(provided_key)
          else
            api_key_path = File.join(Dir.home, '.secrets', 'XAI_API_KEY')

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
      end
    end
  end
end
