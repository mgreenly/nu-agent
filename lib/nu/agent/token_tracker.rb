# frozen_string_literal: true

module Nu
  module Agent
    class TokenTracker
      attr_reader :total_input_tokens, :total_output_tokens

      def initialize
        @total_input_tokens = 0
        @total_output_tokens = 0
      end

      def track(input_tokens, output_tokens)
        @total_input_tokens += input_tokens || 0
        @total_output_tokens += output_tokens || 0
      end

      def total_tokens
        @total_input_tokens + @total_output_tokens
      end
    end
  end
end