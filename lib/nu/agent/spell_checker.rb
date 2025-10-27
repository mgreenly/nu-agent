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
        add_spell_check_request(text)
        spell_check_messages = spell_check_messages_from_history
        response = @client.send_message(messages: spell_check_messages, system_prompt: SYSTEM_PROMPT)
        corrected_text = response["content"].strip
        save_corrected_response(corrected_text, response)
        corrected_text
      rescue StandardError
        text
      end

      private

      def add_spell_check_request(text)
        prompt = <<~PROMPT
          Fix ONLY misspelled words in the following text. Do NOT change capitalization, grammar, or punctuation. Return ONLY the corrected text with no explanations:

          #{text}
        PROMPT
        @history.add_message(
          conversation_id: @conversation_id, actor: ACTOR, role: "user", content: prompt, redacted: true
        )
      end

      def spell_check_messages_from_history
        messages = @history.messages(conversation_id: @conversation_id, include_in_context_only: true)
        messages.select { |m| m["actor"] == ACTOR }
      end

      def save_corrected_response(corrected_text, response)
        @history.add_message(
          conversation_id: @conversation_id, actor: ACTOR, role: "assistant", content: corrected_text,
          model: response["model"], tokens_input: response["tokens"]["input"],
          tokens_output: response["tokens"]["output"], spend: response["spend"], redacted: true
        )
      end
    end
  end
end
