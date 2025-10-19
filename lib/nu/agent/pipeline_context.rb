# frozen_string_literal: true

module Nu
  module Agent
    # Carries state through the prompt processing pipeline
    class PipelineContext
      attr_reader :original_prompt, :current_prompt, :metadata

      def initialize(original_prompt:)
        @original_prompt = original_prompt
        @current_prompt = original_prompt
        @metadata = {}
        @halted = false
        @clarifications = {}
      end

      def update_prompt(new_prompt)
        @current_prompt = new_prompt
        self
      end

      def final_prompt
        @current_prompt
      end

      def halt!
        @halted = true
      end

      def halted?
        @halted
      end

      def store(key, value)
        @metadata[key] = value
      end

      def retrieve(key)
        @metadata[key]
      end

      def add_clarification(term, answer)
        @clarifications[term] = answer
      end

      def clarifications
        @clarifications
      end

      def has_clarifications?
        !@clarifications.empty?
      end
    end
  end
end