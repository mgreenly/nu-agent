# frozen_string_literal: true

module Nu
  module Agent
    module Clients
      class XAI < OpenAI
        # Explicit imports for external dependencies
        ApiKey = ::Nu::Agent::ApiKey
        Error = ::Nu::Agent::Error

        # Default model (cheapest option)
        DEFAULT_MODEL = 'grok-code-fast-1'

        # Model configurations (verified 2025-10-21)
        MODELS = {
          'grok-3' => {
            display_name: 'Grok 3',
            max_context: 1_000_000,
            pricing: { input: 3.00, output: 15.00 }
          },
          'grok-code-fast-1' => {
            display_name: 'Grok Code Fast 1',
            max_context: 256_000,
            pricing: { input: 0.20, output: 1.50 }
          }
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
            models: MODELS.map { |id, info| { id: id, display_name: info[:display_name] } }
          }
        end

        def max_context
          MODELS.dig(@model, :max_context) || MODELS.dig('grok-3', :max_context)
        end

        def calculate_cost(input_tokens:, output_tokens:)
          return 0.0 if input_tokens.nil? || output_tokens.nil?

          pricing = MODELS.dig(@model, :pricing) || MODELS.dig('grok-3', :pricing)
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
