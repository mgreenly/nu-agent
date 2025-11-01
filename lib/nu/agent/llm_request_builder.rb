# frozen_string_literal: true

module Nu
  module Agent
    # Builder for constructing LLM requests in an internal format
    # that can be translated to specific LLM provider APIs
    class LlmRequestBuilder
      attr_reader :system_prompt

      def initialize
        @system_prompt = nil
      end

      def with_system_prompt(prompt)
        @system_prompt = prompt
        self
      end
    end
  end
end
