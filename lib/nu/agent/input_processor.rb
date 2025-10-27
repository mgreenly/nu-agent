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
        return application.handle_command(input) if input.start_with?("/")

        setup_exchange_tracking
        thread = nil
        workers_incremented = false

        begin
          workers_incremented = true
          application.history.increment_workers

          thread = spawn_orchestrator_thread(input)
          application.active_threads << thread

          wait_for_thread_completion
        rescue Interrupt
          handle_interrupt_cleanup(thread, workers_incremented)
        ensure
          cleanup_resources(thread)
        end

        :continue
      end

      private

      def formatter
        application.formatter
      end

      def setup_exchange_tracking
        application.formatter.exchange_start_time = Time.now
        application.console.show_spinner("Thinking...")
      end

      def spawn_orchestrator_thread(input)
        application.operation_mutex.synchronize do
          state = capture_application_state(input)
          formatter.display_thread_event("Orchestrator", "Starting")

          orchestrator = create_chat_orchestrator(state[:hist], state[:fmt], state[:app])
          create_orchestrator_thread(state, orchestrator)
        end
      end

      def capture_application_state(input)
        {
          conv_id: application.conversation_id,
          hist: application.history,
          cli: application.orchestrator,
          session_start: application.session_start_time,
          user_in: input,
          fmt: application.formatter,
          app: application
        }
      end

      def create_chat_orchestrator(hist, fmt, app)
        ChatLoopOrchestrator.new(
          history: hist,
          formatter: fmt,
          application: app,
          user_actor: user_actor
        )
      end

      def create_orchestrator_thread(state, orchestrator)
        context = {
          session_start_time: state[:session_start],
          user_input: state[:user_in],
          application: state[:app]
        }

        Thread.new(state[:conv_id], state[:hist], state[:cli], context,
                   orchestrator) do |conversation_id, history, client, ctx, orch|
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

      def wait_for_thread_completion
        formatter.wait_for_completion(conversation_id: application.conversation_id)
        formatter.display_thread_event("Orchestrator", "Finished")
      end

      def handle_interrupt_cleanup(thread, workers_incremented)
        application.console.hide_spinner
        application.output_line("(Ctrl-C) Operation aborted by user.", type: :debug)

        # Kill all active threads (orchestrator, summarizer, etc.)
        application.active_threads.each do |t|
          t.kill if t.alive?
        end
        application.active_threads.clear

        # Clean up worker count if needed
        return unless thread&.alive? || workers_incremented

        # Decrement if thread is alive or workers were incremented but thread wasn't created yet
        application.history.decrement_workers
      end

      def cleanup_resources(thread)
        application.console.hide_spinner
        application.active_threads.delete(thread) if thread
      end
    end
  end
end
