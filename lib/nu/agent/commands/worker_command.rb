# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to manage background workers
      class WorkerCommand < BaseCommand
        WORKER_NAMES = %w[conversation-summarizer exchange-summarizer embeddings].freeze

        def execute(input)
          parts = input.split
          args = parts[1..] || []

          if args.empty? || args.first == "help"
            show_general_help
          elsif args.first == "status"
            show_all_status
          elsif WORKER_NAMES.include?(args.first)
            delegate_to_worker(args.first, args[1..])
          else
            show_error(args.first)
          end

          :continue
        end

        private

        def show_general_help
          app.console.puts("")
          app.output_lines(*help_text.lines.map(&:chomp), type: :command)
        end

        def show_all_status
          app.console.puts("")
          app.output_lines(*status_text.lines.map(&:chomp), type: :command)
        end

        def delegate_to_worker(worker_name, args)
          handler = create_worker_handler(worker_name)
          subcommand = args.empty? ? "help" : args.first
          remaining_args = args[1..] || []
          handler.execute_subcommand(subcommand, remaining_args)
        end

        def create_worker_handler(worker_name)
          case worker_name
          when "conversation-summarizer"
            require_relative "workers/conversation_summarizer_command"
            Workers::ConversationSummarizerCommand.new(app)
          when "exchange-summarizer"
            require_relative "workers/exchange_summarizer_command"
            Workers::ExchangeSummarizerCommand.new(app)
          when "embeddings"
            require_relative "workers/embeddings_command"
            Workers::EmbeddingsCommand.new(app)
          end
        end

        def show_error(invalid_worker)
          app.console.puts("")
          app.output_line("Unknown worker: #{invalid_worker}", type: :command)
          app.output_line("Available workers: #{WORKER_NAMES.join(', ')}", type: :command)
        end

        def help_text
          <<~HELP
            Available workers:
              conversation-summarizer    - Summarizes completed conversations
              exchange-summarizer        - Summarizes individual exchanges
              embeddings                 - Generates embeddings for RAG

            Commands:
              /worker                              - Show this help
              /worker status                       - Show all workers summary
              /worker <name>                       - Show worker-specific help
              /worker <name> on|off                - Enable/disable worker (persistent + immediate)
              /worker <name> start|stop            - Start/stop worker now (runtime only)
              /worker <name> status                - Show detailed statistics
              /worker <name> model [name]          - Show/change model
              /worker <name> verbosity <0-6>       - Set worker debug verbosity (0=minimal, 6=verbose)
              /worker <name> reset                 - Clear worker's database

            Worker-specific commands:
              /worker embeddings batch <size>      - Set embedding batch size
              /worker embeddings rate <ms>         - Set embedding rate limit (milliseconds)

            Examples:
              /worker status                                    - View all workers
              /worker conversation-summarizer status            - View detailed stats
              /worker exchange-summarizer model claude-opus-4-1 - Change model
              /worker embeddings verbosity 2                    - Set verbosity to level 2
              /worker embeddings reset                          - Clear all embeddings
          HELP
        end

        def status_text
          lines = ["Workers:"]
          lines.concat(worker_status_lines("conversation-summarizer", app.worker_manager.summarizer_status,
                                           "claude-sonnet-4-5"))
          lines.concat(worker_status_lines("exchange-summarizer", app.worker_manager.exchange_summarizer_status,
                                           "claude-sonnet-4-5"))
          lines.concat(worker_status_lines("embeddings", app.worker_manager.embedding_status,
                                           "text-embedding-3-small (read-only)"))
          lines.join("\n")
        end

        def worker_status_lines(name, status, model)
          state = status["running"] ? "running" : "idle"
          verbosity = load_worker_verbosity(name)
          [
            "  #{name}: enabled, #{state}, model=#{model}, verbosity=#{verbosity}",
            "    └─ #{status['completed']} completed, #{status['failed']} failed, " \
            "$#{format('%.2f', status['spend'])} spent"
          ]
        end

        def load_worker_verbosity(worker_name)
          config_key = case worker_name
                       when "conversation-summarizer"
                         "conversation_summarizer_verbosity"
                       when "exchange-summarizer"
                         "exchange_summarizer_verbosity"
                       when "embeddings"
                         "embeddings_verbosity"
                       end
          app.history.get_int(config_key, default: 0)
        end
      end
    end
  end
end
