# frozen_string_literal: true

module Nu
  module Agent
    class ModelFactory
      # Anthropic model mappings
      ANTHROPIC_MODELS = {
        # Claude Sonnet 4.5
        'claude-sonnet-4-5-20250929' => 'claude-sonnet-4-5-20250929',
        'claude-sonnet-4-5' => 'claude-sonnet-4-5-20250929',
        'sonnet' => 'claude-sonnet-4-5-20250929',

        # Claude Haiku 4.5
        'claude-haiku-4-5-20251001' => 'claude-haiku-4-5-20251001',
        'claude-haiku-4-5' => 'claude-haiku-4-5-20251001',
        'haiku' => 'claude-haiku-4-5-20251001',

        # Claude Opus 4.1
        'claude-opus-4-1-20250805' => 'claude-opus-4-1-20250805',
        'claude-opus-4-1' => 'claude-opus-4-1-20250805',
        'opus' => 'claude-opus-4-1-20250805',
      }.freeze

      # Google/Gemini model mappings
      GOOGLE_MODELS = {
        'gemini-2.0-flash-exp' => 'gemini-2.0-flash-exp',
        'gemini-2.0-flash' => 'gemini-2.0-flash-exp',
        'gemini' => 'gemini-2.0-flash-exp',
      }.freeze

      # OpenAI model mappings
      OPENAI_MODELS = {
        'gpt-5' => 'gpt-5',
        'gpt-4o' => 'gpt-4o',
        'gpt-4o-mini' => 'gpt-4o-mini',
        'gpt-4-turbo' => 'gpt-4-turbo',
        'gpt-4' => 'gpt-4',
        'gpt-3.5-turbo' => 'gpt-3.5-turbo',
      }.freeze

      # Default model if none specified
      DEFAULT_MODEL = 'sonnet'

      class << self
        def create(model_name = nil)
          model_name ||= DEFAULT_MODEL
          model_name = model_name.to_s.downcase.strip

          # Check which provider this model belongs to
          if ANTHROPIC_MODELS.key?(model_name)
            actual_model = ANTHROPIC_MODELS[model_name]
            Clients::Anthropic.new(model: actual_model)
          elsif GOOGLE_MODELS.key?(model_name)
            actual_model = GOOGLE_MODELS[model_name]
            Clients::Google.new(model: actual_model)
          elsif OPENAI_MODELS.key?(model_name)
            actual_model = OPENAI_MODELS[model_name]
            Clients::OpenAI.new(model: actual_model)
          else
            raise Error, unknown_model_error(model_name)
          end
        end

        def available_models
          {
            anthropic: ANTHROPIC_MODELS.keys,
            google: GOOGLE_MODELS.keys,
            openai: OPENAI_MODELS.keys
          }
        end

        def display_models
          {
            anthropic: ['claude-sonnet-4-5', 'claude-haiku-4-5', 'claude-opus-4-1'],
            google: GOOGLE_MODELS.keys,
            openai: OPENAI_MODELS.keys
          }
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
          ERROR
        end
      end
    end
  end
end
