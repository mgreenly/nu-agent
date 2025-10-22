# frozen_string_literal: true

module Nu
  module Agent
    class SpellChecker
      ACTOR = 'spell_checker'

      def initialize(history:, conversation_id:)
        @history = history
        @conversation_id = conversation_id
        @client = ModelFactory.create('gpt-5-nano')
      end

      def check_spelling(text)
        # Add spell check request to history (not in context for main model)
        @history.add_message(
          conversation_id: @conversation_id,
          actor: ACTOR,
          role: 'user',
          content: "Fix any spelling errors in the following text. Return ONLY the corrected text with no explanations or additional commentary:\n\n#{text}",
          include_in_context: false
        )

        # Get messages for this conversation (including those not in context)
        messages = @history.messages(
          conversation_id: @conversation_id,
          include_in_context_only: false
        )

        # Only send the spell check related messages
        spell_check_messages = messages.select { |m| m['actor'] == ACTOR }

        # Call gpt-5-nano to fix spelling
        response = @client.send_message(
          messages: spell_check_messages,
          system_prompt: "You are a spell checker. Fix spelling errors and return only the corrected text."
        )

        corrected_text = response['content'].strip

        # Add the corrected response to history (not in context for main model)
        @history.add_message(
          conversation_id: @conversation_id,
          actor: ACTOR,
          role: 'assistant',
          content: corrected_text,
          model: response['model'],
          tokens_input: response['tokens']['input'],
          tokens_output: response['tokens']['output'],
          spend: response['spend'],
          include_in_context: false
        )

        corrected_text
      rescue => e
        # On error, return original text
        text
      end
    end
  end
end
