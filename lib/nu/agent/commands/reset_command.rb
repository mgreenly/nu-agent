# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to reset the conversation
      class ResetCommand < BaseCommand
        def execute(_input)
          clear_display
          setup_new_conversation
          app.start_summarization_worker

          :continue
        end

        private

        def clear_display
          app.clear_screen
        end

        def setup_new_conversation
          app.conversation_id = app.history.create_conversation
          app.session_start_time = Time.now
          app.formatter.reset_session(conversation_id: app.conversation_id)
          app.console.puts("")
          app.output_line("Conversation reset", type: :debug)
        end
      end
    end
  end
end
