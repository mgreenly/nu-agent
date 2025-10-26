# frozen_string_literal: true

module Nu
  module Agent
    class ClientFactory
      # Supported models by provider
      ANTHROPIC_MODELS = ["claude-haiku-4-5", "claude-sonnet-4-5", "claude-opus-4-1"].freeze
      GOOGLE_MODELS = ["gemini-2.5-flash-lite", "gemini-2.5-flash", "gemini-2.5-pro"].freeze
      OPENAI_MODELS = ["gpt-5-nano-2025-08-07", "gpt-5-mini", "gpt-5"].freeze
      XAI_MODELS = %w[grok-3 grok-code-fast-1].freeze

      class << self
        def create(model_name)
          raise Error, "Model name is required" if model_name.nil? || model_name.to_s.strip.empty?

          model_name = model_name.to_s.downcase.strip

          # Check which provider this model belongs to
          if ANTHROPIC_MODELS.include?(model_name)
            Clients::Anthropic.new(model: model_name)
          elsif GOOGLE_MODELS.include?(model_name)
            Clients::Google.new(model: model_name)
          elsif OPENAI_MODELS.include?(model_name)
            Clients::OpenAI.new(model: model_name)
          elsif XAI_MODELS.include?(model_name)
            Clients::XAI.new(model: model_name)
          else
            raise Error, unknown_model_error(model_name)
          end
        end

        def available_models
          {
            anthropic: ANTHROPIC_MODELS,
            google: GOOGLE_MODELS,
            openai: OPENAI_MODELS,
            xai: XAI_MODELS
          }
        end

        def display_models
          available_models
        end

        private

        def unknown_model_error(model_name)
          available = available_models
          <<~ERROR
            Unknown model: '#{model_name}'

            Available Anthropic models:
              #{available[:anthropic].join(', ')}

            Available Google models:
              #{available[:google].join(', ')}

            Available OpenAI models:
              #{available[:openai].join(', ')}

            Available X.AI models:
              #{available[:xai].join(', ')}
          ERROR
        end
      end
    end
  end
end
