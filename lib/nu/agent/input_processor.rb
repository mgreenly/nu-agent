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
        worker_token = WorkerToken.new(application.history)
        thread = nil

        begin
          worker_token.activate
          thread = spawn_orchestrator_thread(input, worker_token)
          application.active_threads << thread

          wait_for_thread_completion
        rescue Interrupt
          handle_interrupt_cleanup(thread, worker_token)
        ensure
          cleanup_resources(thread, worker_token)
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

      def spawn_orchestrator_thread(input, worker_token)
        application.operation_mutex.synchronize do
          state = capture_application_state(input)
          formatter.display_thread_event("Orchestrator", "Starting")

          orchestrator = create_chat_orchestrator(state[:hist], state[:fmt], state[:app])
          create_orchestrator_thread(state, orchestrator, worker_token)
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

      def create_orchestrator_thread(state, orchestrator, worker_token)
        context = {
          session_start_time: state[:session_start],
          user_input: state[:user_in],
          application: state[:app]
        }

        Thread.new(state[:conv_id], state[:cli], context, orchestrator,
                   worker_token) do |conv_id, client, ctx, orch, token|
          Thread.current.report_on_exception = false

          tool_registry = ToolRegistry.new
          orch.execute(
            conversation_id: conv_id,
            client: client,
            tool_registry: tool_registry,
            **ctx
          )
        ensure
          token.release # Thread always releases its token
        end
      end

      def wait_for_thread_completion
        formatter.wait_for_completion(conversation_id: application.conversation_id)
        formatter.display_thread_event("Orchestrator", "Finished")
      end

      def handle_interrupt_cleanup(_thread, worker_token)
        # Spinner already cleaned up its display in rescue block
        # Just output the abort message
        application.output_line("(Ctrl-C) Operation aborted by user.", type: :debug)

        # Kill all active threads immediately (orchestrator, summarizer, etc.)
        application.active_threads.each do |t|
          t.kill if t.alive?
        end
        application.active_threads.clear

        # Release worker token if still active
        worker_token.release
      end

      def cleanup_resources(thread, worker_token)
        application.console.hide_spinner
        application.active_threads.delete(thread) if thread
        # Final safety net - release token if somehow still active
        worker_token.release
      end
    end
  end
end
