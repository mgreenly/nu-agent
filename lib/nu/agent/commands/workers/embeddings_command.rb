# frozen_string_literal: true

module Nu
  module Agent
    module Commands
      module Workers
        # Command handler for embeddings worker
        class EmbeddingsCommand
          WORKER_NAME = "embeddings"

          def initialize(application)
            @app = application
          end

          def execute_subcommand(subcommand, args)
            handle_subcommand(subcommand, args)
            :continue
          end

          def handle_subcommand(subcommand, args) # rubocop:disable Metrics/CyclomaticComplexity
            case subcommand
            when "help" then show_help
            when "on" then enable_worker
            when "off" then disable_worker
            when "start" then start_worker
            when "stop" then stop_worker
            when "status" then show_status
            when "model" then show_model
            when "verbosity" then handle_verbosity(args)
            when "batch" then handle_batch(args)
            when "rate" then handle_rate(args)
            when "reset" then reset_worker
            else show_error(subcommand)
            end
          end

          private

          attr_reader :app

          def show_help
            app.console.puts("")
            app.output_lines(*help_text.lines.map(&:chomp), type: :debug)
          end

          def enable_worker
            app.history.set_config("embeddings_enabled", "true")
            app.worker_manager.enable_worker(WORKER_NAME)
            app.console.puts("")
            app.output_line("#{WORKER_NAME}=on", type: :debug)
          end

          def disable_worker
            app.history.set_config("embeddings_enabled", "false")
            app.worker_manager.disable_worker(WORKER_NAME)
            app.console.puts("")
            app.output_line("#{WORKER_NAME}=off", type: :debug)
          end

          def start_worker
            app.worker_manager.start_worker(WORKER_NAME)
            app.console.puts("")
            app.output_line("Starting #{WORKER_NAME} worker", type: :debug)
          end

          def stop_worker
            app.worker_manager.stop_worker(WORKER_NAME)
            app.console.puts("")
            app.output_line("Stopping #{WORKER_NAME} worker", type: :debug)
          end

          def show_status
            app.console.puts("")
            app.output_lines(*status_text.lines.map(&:chomp), type: :debug)
          end

          def show_model
            app.console.puts("")
            app.output_line("#{WORKER_NAME} model: text-embedding-3-small (read-only)", type: :debug)
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
            app.output_line("Usage: /worker #{WORKER_NAME} verbosity <0-6>", type: :debug)
          end

          def change_verbosity(level)
            level_int = Integer(level)
            unless (0..6).cover?(level_int)
              show_verbosity_error
              return
            end

            app.history.set_config("embeddings_verbosity", level)
            app.console.puts("")
            app.output_line("#{WORKER_NAME} verbosity: #{level}", type: :debug)
          rescue ArgumentError
            show_verbosity_error
          end

          def show_verbosity_error
            app.console.puts("")
            app.output_line("Invalid verbosity level. Use 0-6.", type: :debug)
          end

          def handle_batch(args)
            if args.empty?
              show_current_batch
            else
              change_batch(args.first)
            end
          end

          def show_current_batch
            batch_size = app.history.get_int("embedding_batch_size", 10)
            app.console.puts("")
            app.output_line("#{WORKER_NAME} batch size: #{batch_size}", type: :debug)
          end

          def change_batch(size)
            size_int = Integer(size)
            unless size_int.positive?
              show_batch_error
              return
            end

            app.history.set_config("embedding_batch_size", size)
            app.console.puts("")
            app.output_line("#{WORKER_NAME} batch size: #{size}", type: :debug)
          rescue ArgumentError
            show_batch_error
          end

          def show_batch_error
            app.console.puts("")
            app.output_line("Invalid batch size. Must be a positive integer.", type: :debug)
          end

          def handle_rate(args)
            if args.empty?
              show_current_rate
            else
              change_rate(args.first)
            end
          end

          def show_current_rate
            rate_limit = app.history.get_int("embedding_rate_limit_ms", 100)
            app.console.puts("")
            app.output_line("#{WORKER_NAME} rate limit: #{rate_limit}ms", type: :debug)
          end

          def change_rate(limit)
            limit_int = Integer(limit)
            if limit_int.negative?
              show_rate_error
              return
            end

            app.history.set_config("embedding_rate_limit_ms", limit)
            app.console.puts("")
            app.output_line("#{WORKER_NAME} rate limit: #{limit}ms", type: :debug)
          rescue ArgumentError
            show_rate_error
          end

          def show_rate_error
            app.console.puts("")
            app.output_line("Invalid rate limit. Must be a non-negative integer.", type: :debug)
          end

          def reset_worker
            app.history.clear_all_embeddings
            app.console.puts("")
            app.output_line("Cleared all embeddings", type: :debug)
          end

          def show_error(subcommand)
            app.console.puts("")
            app.output_line("Unknown subcommand: #{subcommand}", type: :debug)
            app.output_line("Use: /worker #{WORKER_NAME} help", type: :debug)
          end

          def help_text
            <<~HELP
              Embeddings Worker

              Generates embeddings for conversations and exchanges to enable RAG retrieval.

              Commands:
                /worker #{WORKER_NAME}                 - Show this help
                /worker #{WORKER_NAME} on|off         - Enable/disable worker
                /worker #{WORKER_NAME} start|stop     - Start/stop worker now
                /worker #{WORKER_NAME} status         - Show detailed statistics
                /worker #{WORKER_NAME} model          - Show embedding model (read-only)
                /worker #{WORKER_NAME} verbosity <0-6> - Set debug verbosity level
                /worker #{WORKER_NAME} batch <size>   - Set/show batch size
                /worker #{WORKER_NAME} rate <ms>      - Set/show rate limit (milliseconds)
                /worker #{WORKER_NAME} reset          - Clear all embeddings

              Verbosity Levels (when /debug is on):
                0 - Worker lifecycle only (start/stop/errors)
                1 - Batch processing start/complete
                2 - Individual items being processed
                3 - Full details (API responses, costs)

              Examples:
                /worker #{WORKER_NAME} status         - View current stats
                /worker #{WORKER_NAME} batch 20       - Set batch size to 20
                /worker #{WORKER_NAME} rate 200       - Set rate limit to 200ms
                /worker #{WORKER_NAME} verbosity 2    - Show item-level processing
                /worker #{WORKER_NAME} reset          - Clear and regenerate embeddings
            HELP
          end

          def status_text
            status = app.worker_manager.worker_status(WORKER_NAME)
            enabled = app.worker_manager.worker_enabled?(WORKER_NAME) ? "yes" : "no"
            state = status["running"] ? "running" : "idle"
            verbosity = app.history.get_int("embeddings_verbosity", 0)
            batch_size = app.history.get_int("embedding_batch_size", 10)
            rate_limit = app.history.get_int("embedding_rate_limit_ms", 100)

            <<~STATUS
              Embeddings Worker Status:
                Enabled: #{enabled}
                State: #{state}
                Model: text-embedding-3-small (read-only)
                Verbosity: #{verbosity}
                Batch size: #{batch_size}
                Rate limit: #{rate_limit}ms

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
