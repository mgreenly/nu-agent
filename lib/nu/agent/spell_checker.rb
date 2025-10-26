# frozen_string_literal: true

module Nu
  module Agent
    class SpellChecker
      ACTOR = "spell_checker"
      SYSTEM_PROMPT = "You are a spell checker. Fix ONLY misspelled words. " \
                      "Do NOT change capitalization, grammar, punctuation, or style. " \
                      "Return only the corrected text."

      def initialize(history:, conversation_id:, client:)
        @history = history
        @conversation_id = conversation_id
        @client = client
      end

      def check_spelling(text)
        # Add spell check request to history
        prompt = <<~PROMPT
          Fix ONLY misspelled words in the following text. Do NOT change capitalization, grammar, or punctuation. Return ONLY the corrected text with no explanations:

          #{text}
        PROMPT
        @history.add_message(
          conversation_id: @conversation_id,
          actor: ACTOR,
          role: "user",
          content: prompt,
          redacted: true
        )

        # Get messages for this conversation
        messages = @history.messages(
          conversation_id: @conversation_id,
          include_in_context_only: true
        )

        # Only send the spell check related messages
        spell_check_messages = messages.select { |m| m["actor"] == ACTOR }

        # Call gemini-2.5-flash to fix spelling
        response = @client.send_message(
          messages: spell_check_messages,
          system_prompt: SYSTEM_PROMPT
        )

        corrected_text = response["content"].strip

        # Add the corrected response to history
        @history.add_message(
          conversation_id: @conversation_id,
          actor: ACTOR,
          role: "assistant",
          content: corrected_text,
          model: response["model"],
          tokens_input: response["tokens"]["input"],
          tokens_output: response["tokens"]["output"],
          spend: response["spend"],
          redacted: true
        )

        corrected_text
      rescue StandardError
        # On error, return original text
        text
      end
    end
  end
end
