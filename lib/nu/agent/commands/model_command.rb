# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to switch models for orchestrator or summarizer
      class ModelCommand < BaseCommand
        def execute(input)
          parts = input.split

          # /model without arguments - show current models
          if parts.length == 1
            show_current_models
            return :continue
          end

          # /model <subcommand> <name>
          if parts.length < 3
            show_usage
            return :continue
          end

          subcommand = parts[1].strip.downcase
          new_model_name = parts[2].strip

          case subcommand
          when "orchestrator"
            switch_orchestrator(new_model_name)
          when "summarizer"
            switch_summarizer(new_model_name)
          else
            show_unknown_subcommand(subcommand)
          end

          :continue
        end

        private

        def show_current_models
          app.console.puts("")
          app.output_line("Current Models:", type: :command)
          app.output_line("  Orchestrator:  #{app.orchestrator.model}", type: :command)
          app.output_line("  Summarizer:    #{app.summarizer.model}", type: :command)
        end

        def show_usage
          app.console.puts("")
          app.output_line("Usage:", type: :command)
          app.output_line("  /model                        Show current models", type: :command)
          app.output_line("  /model orchestrator <name>    Set orchestrator model", type: :command)
          app.output_line("  /model summarizer <name>      Set summarizer model", type: :command)
          app.output_line("Example: /model orchestrator gpt-5", type: :command)
          app.output_line("Run /models to see available models", type: :command)
        end

        def switch_orchestrator(new_model_name)
          app.operation_mutex.synchronize do
            wait_for_active_threads
            new_client = create_client_safely(new_model_name)
            return unless new_client

            apply_orchestrator_switch(new_client, new_model_name)
          end
        end

        def wait_for_active_threads
          return if app.active_threads.empty?

          still_running = app.active_threads.any? { |thread| !thread.join(0.05) }

          return unless still_running

          app.output_line("Waiting for current operation to complete...", type: :command)
          app.active_threads.each(&:join)
        end

        def create_client_safely(model_name)
          ClientFactory.create(model_name)
        rescue Error => e
          app.output_line("Error: #{e.message}", type: :error)
          nil
        end

        def apply_orchestrator_switch(new_client, model_name)
          app.orchestrator = new_client
          app.formatter.orchestrator = new_client
          app.history.set_config("model_orchestrator", model_name)

          app.console.puts("")
          app.output_line("Switched orchestrator to: #{app.orchestrator.name} (#{app.orchestrator.model})",
                          type: :command)
        end

        def switch_summarizer(new_model_name)
          # Create new client
          new_client = ClientFactory.create(new_model_name)
          app.summarizer = new_client
          app.history.set_config("model_summarizer", new_model_name)
          app.console.puts("")
          app.output_line("Switched summarizer to: #{new_model_name}", type: :command)
          app.output_line("Note: Change takes effect at the start of the next session (/reset)", type: :command)
        rescue Error => e
          app.console.puts("")
          app.output_line("Error: #{e.message}", type: :error)
        end

        def show_unknown_subcommand(subcommand)
          app.console.puts("")
          app.output_line("Unknown subcommand: #{subcommand}", type: :command)
          app.output_line("Valid subcommands: orchestrator, summarizer", type: :command)
        end
      end
    end
  end
end
