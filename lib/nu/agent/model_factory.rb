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
        # Embedding models
        'embedding-gecko-001' => 'embedding-gecko-001',
        'embedding-001' => 'embedding-001',
        'text-embedding-004' => 'text-embedding-004',
        'gemini-embedding-exp-03-07' => 'gemini-embedding-exp-03-07',
        'gemini-embedding-exp' => 'gemini-embedding-exp',
        'gemini-embedding-001' => 'gemini-embedding-001',

        # Gemini 2.5 models
        'gemini-2.5-pro-preview-03-25' => 'gemini-2.5-pro-preview-03-25',
        'gemini-2.5-flash-preview-05-20' => 'gemini-2.5-flash-preview-05-20',
        'gemini-2.5-flash' => 'gemini-2.5-flash',
        'gemini-2.5-flash-lite-preview-06-17' => 'gemini-2.5-flash-lite-preview-06-17',
        'gemini-2.5-pro-preview-05-06' => 'gemini-2.5-pro-preview-05-06',
        'gemini-2.5-pro-preview-06-05' => 'gemini-2.5-pro-preview-06-05',
        'gemini-2.5-pro' => 'gemini-2.5-pro',
        'gemini-2.5-flash-lite' => 'gemini-2.5-flash-lite',
        'gemini-2.5-flash-image-preview' => 'gemini-2.5-flash-image-preview',
        'gemini-2.5-flash-image' => 'gemini-2.5-flash-image',
        'gemini-2.5-flash-preview-09-2025' => 'gemini-2.5-flash-preview-09-2025',
        'gemini-2.5-flash-lite-preview-09-2025' => 'gemini-2.5-flash-lite-preview-09-2025',
        'gemini-2.5-flash-preview-tts' => 'gemini-2.5-flash-preview-tts',
        'gemini-2.5-pro-preview-tts' => 'gemini-2.5-pro-preview-tts',
        'gemini-2.5-computer-use-preview-10-2025' => 'gemini-2.5-computer-use-preview-10-2025',

        # Gemini 2.0 models
        'gemini-2.0-flash-exp' => 'gemini-2.0-flash-exp',
        'gemini-2.0-flash' => 'gemini-2.0-flash',
        'gemini-2.0-flash-001' => 'gemini-2.0-flash-001',
        'gemini-2.0-flash-exp-image-generation' => 'gemini-2.0-flash-exp-image-generation',
        'gemini-2.0-flash-lite-001' => 'gemini-2.0-flash-lite-001',
        'gemini-2.0-flash-lite' => 'gemini-2.0-flash-lite',
        'gemini-2.0-flash-preview-image-generation' => 'gemini-2.0-flash-preview-image-generation',
        'gemini-2.0-flash-lite-preview-02-05' => 'gemini-2.0-flash-lite-preview-02-05',
        'gemini-2.0-flash-lite-preview' => 'gemini-2.0-flash-lite-preview',
        'gemini-2.0-pro-exp' => 'gemini-2.0-pro-exp',
        'gemini-2.0-pro-exp-02-05' => 'gemini-2.0-pro-exp-02-05',
        'gemini-2.0-flash-thinking-exp-01-21' => 'gemini-2.0-flash-thinking-exp-01-21',
        'gemini-2.0-flash-thinking-exp' => 'gemini-2.0-flash-thinking-exp',
        'gemini-2.0-flash-thinking-exp-1219' => 'gemini-2.0-flash-thinking-exp-1219',

        # Experimental models
        'gemini-exp-1206' => 'gemini-exp-1206',

        # Latest aliases
        'gemini-flash-latest' => 'gemini-flash-latest',
        'gemini-flash-lite-latest' => 'gemini-flash-lite-latest',
        'gemini-pro-latest' => 'gemini-pro-latest',

        # LearnLM
        'learnlm-2.0-flash-experimental' => 'learnlm-2.0-flash-experimental',

        # Gemma models
        'gemma-3-1b-it' => 'gemma-3-1b-it',
        'gemma-3-4b-it' => 'gemma-3-4b-it',
        'gemma-3-12b-it' => 'gemma-3-12b-it',
        'gemma-3-27b-it' => 'gemma-3-27b-it',
        'gemma-3n-e4b-it' => 'gemma-3n-e4b-it',
        'gemma-3n-e2b-it' => 'gemma-3n-e2b-it',

        # Robotics
        'gemini-robotics-er-1.5-preview' => 'gemini-robotics-er-1.5-preview',

        # AQA
        'aqa' => 'aqa',

        # Imagen models
        'imagen-3.0-generate-002' => 'imagen-3.0-generate-002',
        'imagen-4.0-generate-preview-06-06' => 'imagen-4.0-generate-preview-06-06',

        # Convenience alias
        'gemini' => 'gemini-2.0-flash-exp',
      }.freeze

      # OpenAI model mappings
      OPENAI_MODELS = {
        'gpt-5-chat-latest' => 'gpt-5-chat-latest',
        'gpt-5' => 'gpt-5',
        'gpt-5-mini' => 'gpt-5-mini',
        'gpt-5-nano-2025-08-07' => 'gpt-5-nano-2025-08-07',
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
            google: ['gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.5-flash-lite'],
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
