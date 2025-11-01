# frozen_string_literal: true

module Nu
  module Agent
    module Commands
      module Workers
        # Command handler for conversation-summarizer worker
        class ConversationSummarizerCommand
          WORKER_NAME = "conversation-summarizer"

          def initialize(application)
            @app = application
          end

          def execute_subcommand(subcommand, args)
            case subcommand
            when "help"
              show_help
            when "on"
              enable_worker
            when "off"
              disable_worker
            when "start"
              start_worker
            when "stop"
              stop_worker
            when "status"
              show_status
            when "model"
              handle_model(args)
            when "verbosity"
              handle_verbosity(args)
            when "reset"
              reset_worker
            else
              show_error(subcommand)
            end

            :continue
          end

          private

          attr_reader :app

          def show_help
            app.console.puts("")
            app.output_lines(*help_text.lines.map(&:chomp), type: :command)
          end

          def enable_worker
            app.history.set_config("conversation_summarizer_enabled", "true")
            app.worker_manager.enable_worker(WORKER_NAME)
            app.console.puts("")
            app.output_line("#{WORKER_NAME}=on", type: :command)
          end

          def disable_worker
            app.history.set_config("conversation_summarizer_enabled", "false")
            app.worker_manager.disable_worker(WORKER_NAME)
            app.console.puts("")
            app.output_line("#{WORKER_NAME}=off", type: :command)
          end

          def start_worker
            app.worker_manager.start_worker(WORKER_NAME)
            app.console.puts("")
            app.output_line("Starting #{WORKER_NAME} worker", type: :command)
          end

          def stop_worker
            app.worker_manager.stop_worker(WORKER_NAME)
            app.console.puts("")
            app.output_line("Stopping #{WORKER_NAME} worker", type: :command)
          end

          def show_status
            app.console.puts("")
            app.output_lines(*status_text.lines.map(&:chomp), type: :command)
          end

          def handle_model(args)
            if args.empty?
              show_current_model
            else
              change_model(args.first)
            end
          end

          def show_current_model
            model = app.history.get_config("conversation_summarizer_model")
            app.console.puts("")
            app.output_line("#{WORKER_NAME} model: #{model}", type: :command)
          end

          def change_model(new_model)
            app.history.set_config("conversation_summarizer_model", new_model)
            app.console.puts("")
            app.output_line("#{WORKER_NAME} model: #{new_model}", type: :command)
            app.output_line("Model will be used on next /reset", type: :command)
          end

          def handle_verbosity(args)
            if args.empty?
              show_verbosity_usage
            else
              change_verbosity(args.first)
            end
          end

          def show_verbosity_usage
            app.console.puts("")
            app.output_line("Usage: /worker #{WORKER_NAME} verbosity <0-6>", type: :command)
          end

          def change_verbosity(level)
            level_int = Integer(level)
            unless (0..6).cover?(level_int)
              show_verbosity_error
              return
            end

            app.history.set_config("conversation_summarizer_verbosity", level)
            app.console.puts("")
            app.output_line("#{WORKER_NAME} verbosity: #{level}", type: :command)
          rescue ArgumentError
            show_verbosity_error
          end

          def show_verbosity_error
            app.console.puts("")
            app.output_line("Invalid verbosity level. Use 0-6.", type: :command)
          end

          def reset_worker
            app.history.clear_conversation_summaries
            app.console.puts("")
            app.output_line("Cleared all conversation summaries", type: :command)
          end

          def show_error(subcommand)
            app.console.puts("")
            app.output_line("Unknown subcommand: #{subcommand}", type: :command)
            app.output_line("Use: /worker #{WORKER_NAME} help", type: :command)
          end

          def help_text
            <<~HELP
              Conversation Summarizer Worker

              Summarizes completed conversations in the background for improved RAG retrieval.

              Commands:
                /worker #{WORKER_NAME}                 - Show this help
                /worker #{WORKER_NAME} on|off         - Enable/disable worker
                /worker #{WORKER_NAME} start|stop     - Start/stop worker now
                /worker #{WORKER_NAME} status         - Show detailed statistics
                /worker #{WORKER_NAME} model [name]   - Show or change summarizer model
                /worker #{WORKER_NAME} verbosity <0-6> - Set debug verbosity level
                /worker #{WORKER_NAME} reset          - Clear all conversation summaries

              Verbosity Levels (when /debug is on):
                0 - Worker lifecycle only (start/stop/errors)
                1 - Processing summaries (conversation start/complete)
                2 - API calls (prompts sent to LLM)
                3 - Full details (responses, costs, retries)

              Examples:
                /worker #{WORKER_NAME} status              - View current stats
                /worker #{WORKER_NAME} model claude-opus-4-1 - Use Opus for summaries
                /worker #{WORKER_NAME} verbosity 1         - Show processing events
                /worker #{WORKER_NAME} reset               - Clear and regenerate summaries
            HELP
          end

          def status_text
            status = app.worker_manager.worker_status(WORKER_NAME)
            enabled = app.worker_manager.worker_enabled?(WORKER_NAME) ? "yes" : "no"
            state = status["running"] ? "running" : "idle"
            model = app.history.get_config("conversation_summarizer_model")
            verbosity = app.history.get_int("conversation_summarizer_verbosity", default: 0)

            <<~STATUS
              Conversation Summarizer Status:
                Enabled: #{enabled}
                State: #{state}
                Model: #{model}
                Verbosity: #{verbosity}

                Statistics:
                  Total processed: #{status['total']}
                  Completed: #{status['completed']}
                  Failed: #{status['failed']}
                  Cost: $#{format('%.2f', status['spend'])}
            STATUS
          end
        end
      end
    end
  end
end
