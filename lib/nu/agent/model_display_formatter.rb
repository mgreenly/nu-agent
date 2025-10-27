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

        # Mark defaults with asterisk
        anthropic_list = models[:anthropic].map { |m| m == anthropic_default ? "#{m}*" : m }.join(", ")
        google_list = models[:google].map { |m| m == google_default ? "#{m}*" : m }.join(", ")
        openai_list = models[:openai].map { |m| m == openai_default ? "#{m}*" : m }.join(", ")
        xai_list = models[:xai].map { |m| m == xai_default ? "#{m}*" : m }.join(", ")

        lines << "Available Models (* = default):"
        lines << "  Anthropic: #{anthropic_list}"
        lines << "  Google:    #{google_list}"
        lines << "  OpenAI:    #{openai_list}"
        lines << "  X.AI:      #{xai_list}"

        lines.join("\n")
      end
    end
  end
end
