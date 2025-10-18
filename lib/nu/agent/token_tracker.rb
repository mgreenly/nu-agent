# frozen_string_literal: true

module Nu
  module Agent
    class TokenTracker
      attr_reader :total_input_tokens, :total_output_tokens, :requests_count

      def initialize
        reset!
      end

      def track(usage)
        return unless usage

        @total_input_tokens += usage['input_tokens'] || 0
        @total_output_tokens += usage['output_tokens'] || 0
        @requests_count += 1
      end

      def total_tokens
        @total_input_tokens + @total_output_tokens
      end

      def average_input_tokens
        return 0 if @requests_count.zero?

        @total_input_tokens.to_f / @requests_count
      end

      def average_output_tokens
        return 0 if @requests_count.zero?

        @total_output_tokens.to_f / @requests_count
      end

      def average_total_tokens
        return 0 if @requests_count.zero?

        total_tokens.to_f / @requests_count
      end

      # Calculate estimated cost based on Claude Sonnet pricing
      # Note: Update these rates based on current pricing
      def estimated_cost(input_rate: 0.000003, output_rate: 0.000015)
        input_cost = @total_input_tokens * input_rate
        output_cost = @total_output_tokens * output_rate
        {
          input_cost: input_cost,
          output_cost: output_cost,
          total_cost: input_cost + output_cost
        }
      end

      def reset!
        @total_input_tokens = 0
        @total_output_tokens = 0
        @requests_count = 0
      end

      def to_h
        {
          total_input_tokens: @total_input_tokens,
          total_output_tokens: @total_output_tokens,
          total_tokens: total_tokens,
          requests_count: @requests_count,
          average_input_tokens: average_input_tokens,
          average_output_tokens: average_output_tokens,
          average_total_tokens: average_total_tokens,
          estimated_cost: estimated_cost
        }
      end

      def to_s
        <<~SUMMARY
          Token Usage Summary:
          ====================
          Requests: #{@requests_count}
          Total Input Tokens: #{@total_input_tokens}
          Total Output Tokens: #{@total_output_tokens}
          Total Tokens: #{total_tokens}

          Averages per Request:
          - Input: #{average_input_tokens.round(2)}
          - Output: #{average_output_tokens.round(2)}
          - Total: #{average_total_tokens.round(2)}

          Estimated Cost: $#{format('%.6f', estimated_cost[:total_cost])}
        SUMMARY
      end
    end
  end
end