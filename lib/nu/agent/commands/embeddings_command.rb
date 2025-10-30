# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to manage embedding pipeline worker
      class EmbeddingsCommand < BaseCommand
        def execute(input)
          parts = input.split(" ", 3)
          subcommand = parts[1]&.strip&.downcase

          case subcommand
          when "status"
            show_status
          when "on", "off"
            toggle_embeddings(subcommand)
          when "start"
            start_worker
          when "reset"
            reset_embeddings
          when "batch"
            update_batch_size(parts[2])
          when "rate"
            update_rate_limit(parts[2])
          else
            show_usage
          end

          :continue
        end

        private

        def show_usage
          app.console.puts("")
          usage_lines.each { |line| app.output_line(line, type: :debug) }
          app.console.puts("")
          app.output_line("Current: embeddings=#{app.embedding_enabled ? 'on' : 'off'}", type: :debug)
        end

        def usage_lines
          [
            "Usage: /embeddings <command>",
            "Commands:",
            "  status              - Show worker status and metrics",
            "  on|off              - Enable/disable embeddings (requires /reset)",
            "  start               - Start embedding worker now",
            "  reset               - Clear all embeddings (forces regeneration)",
            "  batch <size>        - Set batch size (default: 10)",
            "  rate <ms>           - Set rate limit between batches in ms (default: 100)"
          ]
        end

        def show_status
          status = app.embedding_status
          app.console.puts("")
          show_worker_status(status)
          show_worker_progress(status) if status["running"] || status["total"].positive?
          app.console.puts("")
          show_worker_configuration
        end

        def show_worker_status(status)
          app.output_line("Embedding Worker Status:", type: :debug)
          app.output_line("  Enabled: #{app.embedding_enabled ? 'yes' : 'no'}", type: :debug)
          app.output_line("  Running: #{status['running'] ? 'yes' : 'no'}", type: :debug)
        end

        def show_worker_progress(status)
          app.output_line("  Progress: #{status['completed']}/#{status['total']}", type: :debug)
          app.output_line("  Failed: #{status['failed']}", type: :debug)
          app.output_line("  Current: #{status['current_item']}", type: :debug) if status["current_item"]
          app.output_line("  Total spend: $#{format('%.6f', status['spend'])}", type: :debug)
        end

        def show_worker_configuration
          batch_size = app.history.get_config("embedding_batch_size", default: "10")
          rate_limit = app.history.get_config("embedding_rate_limit_ms", default: "100")
          app.output_line("Configuration:", type: :debug)
          app.output_line("  Batch size: #{batch_size}", type: :debug)
          app.output_line("  Rate limit: #{rate_limit}ms", type: :debug)
        end

        def toggle_embeddings(setting)
          enabled = setting == "on"
          app.embedding_enabled = enabled
          app.history.set_config("embedding_enabled", enabled ? "true" : "false")

          app.console.puts("")
          app.output_line("embeddings=#{setting}", type: :debug)
          app.output_line("Embedding worker will start on next /reset", type: :debug) if enabled
        end

        def start_worker
          return show_embeddings_disabled_error unless app.embedding_enabled
          return show_no_client_error unless app.embedding_client
          return show_already_running_message if app.embedding_status["running"]

          start_embedding_worker
        end

        def show_embeddings_disabled_error
          app.console.puts("")
          app.output_line("Embeddings are disabled. Use '/embeddings on' first.", type: :error)
        end

        def show_no_client_error
          app.console.puts("")
          app.output_line("Embedding client not available.", type: :error)
        end

        def show_already_running_message
          app.console.puts("")
          app.output_line("Embedding worker is already running.", type: :debug)
        end

        def start_embedding_worker
          app.console.puts("")
          app.output_line("Starting embedding worker...", type: :debug)
          app.worker_manager.start_embedding_worker
        end

        def update_batch_size(size)
          if size.nil? || size.empty?
            app.console.puts("")
            app.output_line("Usage: /embeddings batch <size>", type: :debug)
            return
          end

          size_int = size.to_i
          if size_int <= 0
            app.console.puts("")
            app.output_line("Batch size must be a positive integer", type: :error)
            return
          end

          app.history.set_config("embedding_batch_size", size)
          app.console.puts("")
          app.output_line("Embedding batch size set to #{size_int}", type: :debug)
          app.output_line("Will take effect on next worker start", type: :debug)
        end

        def update_rate_limit(milliseconds)
          if milliseconds.nil? || milliseconds.empty?
            app.console.puts("")
            app.output_line("Usage: /embeddings rate <milliseconds>", type: :debug)
            return
          end

          ms_int = milliseconds.to_i
          if ms_int.negative?
            app.console.puts("")
            app.output_line("Rate limit must be >= 0", type: :error)
            return
          end

          app.history.set_config("embedding_rate_limit_ms", milliseconds)
          app.console.puts("")
          app.output_line("Embedding rate limit set to #{ms_int}ms", type: :debug)
          app.output_line("Will take effect on next worker start", type: :debug)
        end

        def reset_embeddings
          app.console.puts("")
          app.output_line("Resetting all conversation and exchange embeddings...", type: :debug)

          conv_count = delete_embeddings("conversation_summary")
          exch_count = delete_embeddings("exchange_summary")

          show_reset_results(conv_count, exch_count)
        end

        def delete_embeddings(kind)
          count = app.history.connection.query(<<~SQL).to_a.first[0]
            SELECT COUNT(*) FROM text_embedding_3_small WHERE kind = '#{kind}'
          SQL

          app.history.connection.query(<<~SQL)
            DELETE FROM text_embedding_3_small WHERE kind = '#{kind}'
          SQL

          count
        end

        def show_reset_results(conv_count, exch_count)
          app.console.puts("")
          app.output_line("✓ Cleared #{conv_count} conversation embeddings", type: :debug)
          app.output_line("✓ Cleared #{exch_count} exchange embeddings", type: :debug)
          app.output_line("Worker will regenerate embeddings on next cycle (within 10 seconds)", type: :debug)
          app.console.puts("")
        end
      end
    end
  end
end
