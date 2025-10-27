# frozen_string_literal: true

module Nu
  module Agent
    # Formats available models for display
    class ModelDisplayFormatter
      def self.build
        lines = []
        lines << ""

        models = ClientFactory.display_models

        # Get defaults from each client
        anthropic_default = Nu::Agent::Clients::Anthropic::DEFAULT_MODEL
        google_default = Nu::Agent::Clients::Google::DEFAULT_MODEL
        openai_default = Nu::Agent::Clients::OpenAI::DEFAULT_MODEL
        xai_default = Nu::Agent::Clients::XAI::DEFAULT_MODEL

        lines << "Available Models (* = default):"
        lines << "  Anthropic: #{format_model_list(models[:anthropic], anthropic_default)}"
        lines << "  Google:    #{format_model_list(models[:google], google_default)}"
        lines << "  OpenAI:    #{format_model_list(models[:openai], openai_default)}"
        lines << "  X.AI:      #{format_model_list(models[:xai], xai_default)}"

        lines.join("\n")
      end

      def self.format_model_list(models, default)
        models.map { |m| m == default ? "#{m}*" : m }.join(", ")
      end
    end
  end
end
