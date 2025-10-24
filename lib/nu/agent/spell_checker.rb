# frozen_string_literal: true

module Nu
  module Agent
    class SpellChecker
      ACTOR = 'spell_checker'

      def initialize(history:, conversation_id:)
        @history = history
        @conversation_id = conversation_id
        @client = ClientFactory.create('gemini-2.5-flash')
      end

      def check_spelling(text)
        # Add spell check request to history
        @history.add_message(
          conversation_id: @conversation_id,
          actor: ACTOR,
          role: 'user',
          content: "Fix ONLY misspelled words in the following text. Do NOT change capitalization, grammar, or punctuation. Return ONLY the corrected text with no explanations:\n\n#{text}",
          redacted: true
        )

        # Get messages for this conversation
        messages = @history.messages(
          conversation_id: @conversation_id,
          include_in_context_only: true
        )

        # Only send the spell check related messages
        spell_check_messages = messages.select { |m| m['actor'] == ACTOR }

        # Call gemini-2.5-flash to fix spelling
        response = @client.send_message(
          messages: spell_check_messages,
          system_prompt: "You are a spell checker. Fix ONLY misspelled words. Do NOT change capitalization, grammar, punctuation, or style. Return only the corrected text."
        )

        corrected_text = response['content'].strip

        # Add the corrected response to history
        @history.add_message(
          conversation_id: @conversation_id,
          actor: ACTOR,
          role: 'assistant',
          content: corrected_text,
          model: response['model'],
          tokens_input: response['tokens']['input'],
          tokens_output: response['tokens']['output'],
          spend: response['spend'],
          redacted: true
        )

        corrected_text
      rescue => e
        # On error, return original text
        text
      end
    end
  end
end
