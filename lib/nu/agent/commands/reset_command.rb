# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to reset the conversation
      class ResetCommand < BaseCommand
        def execute(_input)
          # Clear screen (either via TUI or system clear)
          if app.tui&.active
            app.tui.clear_output
          else
            app.clear_screen
          end

          # Create new conversation
          app.conversation_id = app.history.create_conversation
          app.session_start_time = Time.now
          app.formatter.reset_session(conversation_id: app.conversation_id)
          app.console.puts("")
          app.output_line("Conversation reset", type: :debug)

          # Start background summarization worker
          app.start_summarization_worker

          :continue
        end
      end
    end
  end
end
