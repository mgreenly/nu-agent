# frozen_string_literal: true

module Nu
  module Agent
    module RAG
      # Formats retrieved conversations and exchanges into a token-budgeted prompt context
      # Allocates budget across conversations (40%) and exchanges (60%) by default
      # Sorts by similarity with recency as tie-breaker
      class ContextFormatterProcessor < RAGProcessor
        # Rough estimate: 1 token ~= 4 characters for English text
        CHARS_PER_TOKEN = 4

        def initialize(config_store:)
          super()
          @config_store = config_store
        end

        protected

        def process_internal(context)
          # Get token budget configuration
          total_budget = @config_store.get_int("rag_token_budget", default: 2000)
          conversation_pct = @config_store.get_float("rag_conversation_budget_pct", default: 0.4)

          # Calculate token allocations
          conversation_budget = (total_budget * conversation_pct).to_i
          exchange_budget = total_budget - conversation_budget

          # Format sections
          conversation_section = format_conversations(context.conversations, conversation_budget)
          exchange_section = format_exchanges(context.exchanges, exchange_budget)

          # Build final context
          formatted_parts = []
          formatted_parts << conversation_section unless conversation_section.empty?
          formatted_parts << exchange_section unless exchange_section.empty?

          context.formatted_context = formatted_parts.join("\n\n")

          # Update metadata with actual token count
          context.metadata[:total_tokens] = estimate_tokens(context.formatted_context)
        end

        private

        def format_conversations(conversations, token_budget)
          return "" if conversations.empty?

          # Sort by similarity (primary) and recency (tie-breaker)
          sorted = conversations.sort_by do |conv|
            [-conv[:similarity], -conv[:created_at]&.to_time.to_i]
          end

          # Build formatted text within budget
          lines = ["## Related Conversations"]
          char_budget = token_budget * CHARS_PER_TOKEN
          used_chars = lines.first.length + 1 # +1 for newline

          sorted.each do |conv|
            entry = format_conversation_entry(conv)
            entry_chars = entry.length + 1 # +1 for newline

            break if (used_chars + entry_chars) > char_budget

            lines << entry
            used_chars += entry_chars
          end

          # Return empty string if only header (no entries fit)
          return "" if lines.length == 1

          lines.join("\n")
        end

        def format_exchanges(exchanges, token_budget)
          return "" if exchanges.empty?

          # Sort by similarity (primary) and recency (tie-breaker)
          sorted = exchanges.sort_by do |ex|
            [-ex[:similarity], -ex[:started_at]&.to_time.to_i]
          end

          # Build formatted text within budget
          lines = ["## Related Exchanges"]
          char_budget = token_budget * CHARS_PER_TOKEN
          used_chars = lines.first.length + 1 # +1 for newline

          sorted.each do |ex|
            entry = format_exchange_entry(ex)
            entry_chars = entry.length + 1 # +1 for newline

            break if (used_chars + entry_chars) > char_budget

            lines << entry
            used_chars += entry_chars
          end

          # Return empty string if only header (no entries fit)
          return "" if lines.length == 1

          lines.join("\n")
        end

        def format_conversation_entry(conv)
          "- [Conversation ##{conv[:conversation_id]}] #{conv[:content]}"
        end

        def format_exchange_entry(exchange)
          "- [Exchange ##{exchange[:exchange_id]}] #{exchange[:content]}"
        end

        def estimate_tokens(text)
          return 0 if text.nil? || text.empty?

          (text.length.to_f / CHARS_PER_TOKEN).ceil
        end
      end
    end
  end
end
