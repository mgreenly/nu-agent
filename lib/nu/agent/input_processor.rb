# frozen_string_literal: true

module Nu
  module Agent
    class InputProcessor
      attr_reader :application, :user_actor

      def initialize(application:, user_actor:)
        @application = application
        @user_actor = user_actor
      end

      def process(input)
        # Handle commands
        return application.handle_command(input) if input.start_with?("/")

        # Capture exchange start time for elapsed time calculation
        application.formatter.exchange_start_time = Time.now

        # Start spinner
        application.console.show_spinner("Thinking...")

        thread = nil
        workers_incremented = false

        begin
          # Increment workers BEFORE spawning thread
          application.history.increment_workers
          workers_incremented = true

          # Capture values to pass into thread under mutex
          thread = application.operation_mutex.synchronize do
            conv_id = application.conversation_id
            hist = application.history
            cli = application.orchestrator
            session_start = application.session_start_time
            user_in = input
            formatter = application.formatter
            app = application

            # Display thread start event
            formatter.display_thread_event("Orchestrator", "Starting")

            # Spawn orchestrator thread with raw user input
            context = {
              session_start_time: session_start,
              user_input: user_in,
              application: app
            }
            chat_orchestrator = ChatLoopOrchestrator.new(
              history: hist,
              formatter: formatter,
              application: app,
              user_actor: user_actor
            )
            Thread.new(conv_id, hist, cli, context, chat_orchestrator) do |conversation_id, history, client, ctx, orch|
              tool_registry = ToolRegistry.new
              orch.execute(
                conversation_id: conversation_id,
                client: client,
                tool_registry: tool_registry,
                **ctx
              )
            ensure
              history.decrement_workers
            end
          end

          application.active_threads << thread

          # Wait for completion and display
          formatter.wait_for_completion(conversation_id: application.conversation_id)

          # Display thread finished event (after all output is shown)
          formatter.display_thread_event("Orchestrator", "Finished")
        rescue Interrupt
          # Ctrl-C pressed - kill thread and return to prompt
          # Transaction will rollback automatically - no exchange will be saved
          application.console.hide_spinner
          application.output_line("(Ctrl-C) Operation aborted by user.", type: :debug)

          # Kill all active threads (orchestrator, summarizer, etc.)
          application.active_threads.each do |t|
            t.kill if t.alive?
          end
          application.active_threads.clear

          # Clean up worker count if needed
          if thread&.alive? || workers_incremented
            # Decrement if thread is alive or workers were incremented but thread wasn't created yet
            application.history.decrement_workers
          end
        ensure
          # Always stop the spinner
          application.console.hide_spinner
          # Remove completed thread
          application.active_threads.delete(thread) if thread
        end

        :continue
      end

      private

      def formatter
        application.formatter
      end
    end
  end
end
