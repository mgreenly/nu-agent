# frozen_string_literal: true

module Nu
  module Agent
    class SessionStatistics
      def initialize(history:, orchestrator:, console:, conversation_id:, session_start_time:)
        @history = history
        @orchestrator = orchestrator
        @console = console
        @conversation_id = conversation_id
        @session_start_time = session_start_time
      end

      def should_display?(message)
        !!(message["tokens_input"] && message["tokens_output"] && !message["tool_calls"])
      end

      def display(exchange_start_time:, debug:)
        return unless debug

        elapsed_time = exchange_start_time ? Time.now - exchange_start_time : nil

        tokens = @history.session_tokens(
          conversation_id: @conversation_id,
          since: @session_start_time
        )

        display_token_statistics(tokens)
        display_spend_statistics(tokens)
        display_elapsed_time(elapsed_time) if elapsed_time
      end

      private

      def display_token_statistics(tokens)
        max_context = @orchestrator.max_context
        percentage = (tokens["total"].to_f / max_context * 100).round(1)

        @console.puts("")
        inp = tokens["input"]
        out = tokens["output"]
        total = tokens["total"]
        stat_msg = "Session tokens: #{inp} in / #{out} out / #{total} Total / (#{percentage}% of #{max_context})"
        @console.puts("\e[90m#{stat_msg}\e[0m")
      end

      def display_spend_statistics(tokens)
        @console.puts("\e[90mSession spend: $#{format('%.6f', tokens['spend'])}\e[0m")
      end

      def display_elapsed_time(elapsed_time)
        @console.puts("\e[90mElapsed time: #{format('%.2f', elapsed_time)}s\e[0m")
      end
    end
  end
end
