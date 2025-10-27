# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to manage man page indexing (on/off/reset)
      class IndexManCommand < BaseCommand
        def execute(input)
          parts = input.split(" ", 2)

          if parts.length < 2 || parts[1].strip.empty?
            show_usage_and_status
            return :continue
          end

          setting = parts[1].strip.downcase

          case setting
          when "on"
            turn_on
          when "off"
            turn_off
          when "reset"
            reset
          else
            show_invalid_option
          end

          :continue
        end

        private

        def show_usage_and_status
          app.console.puts("")
          app.output_line("Usage: /index-man <on|off|reset>", type: :debug)

          enabled = app.history.get_config("index_man_enabled") == "true"
          app.output_line("Current: index-man=#{enabled ? 'on' : 'off'}", type: :debug)

          # Show status if available
          app.status_mutex.synchronize do
            status = app.man_indexer_status
            if status["running"]
              show_running_status(status)
            elsif status["total"].positive?
              show_completed_status(status)
            end
          end
        end

        def show_running_status(status)
          app.output_line("Status: running (#{status['completed']}/#{status['total']} man pages)", type: :debug)
          app.output_line("Failed: #{status['failed']}, Skipped: #{status['skipped']}", type: :debug)
          app.output_line("Session spend: $#{format('%.6f', status['session_spend'])}", type: :debug)
        end

        def show_completed_status(status)
          app.output_line("Status: completed (#{status['completed']}/#{status['total']} man pages)", type: :debug)
          app.output_line("Failed: #{status['failed']}, Skipped: #{status['skipped']}", type: :debug)
          app.output_line("Session spend: $#{format('%.6f', status['session_spend'])}", type: :debug)
        end

        def turn_on
          app.history.set_config("index_man_enabled", "true")
          app.console.puts("")
          app.output_line("index-man=on", type: :debug)
          app.output_line("Starting man page indexer...", type: :debug)

          # Start the indexer worker
          app.start_man_indexer_worker

          # Show initial status
          sleep(0.5) # Give it a moment to start
          app.status_mutex.synchronize do
            status = app.man_indexer_status
            app.output_line("Indexing #{status['total']} man pages...", type: :debug)
            app.output_line("This will take approximately #{(status['total'] / 10.0 / 60.0).ceil} minutes",
                            type: :debug)
          end
        end

        def turn_off
          app.history.set_config("index_man_enabled", "false")
          app.console.puts("")
          app.output_line("index-man=off", type: :debug)
          app.output_line("Indexer will stop after current batch completes", type: :debug)

          # Show final status
          app.status_mutex.synchronize do
            status = app.man_indexer_status
            if status["completed"].positive?
              app.output_line("Indexed: #{status['completed']}/#{status['total']} man pages", type: :debug)
              app.output_line("Failed: #{status['failed']}, Skipped: #{status['skipped']}", type: :debug)
              app.output_line("Session spend: $#{format('%.6f', status['session_spend'])}", type: :debug)
            end
          end
        end

        def reset
          # Stop indexing if running
          if app.history.get_config("index_man_enabled") == "true"
            app.history.set_config("index_man_enabled", "false")
            app.console.puts("")
            app.output_line("Stopping indexer before reset...", type: :debug)
            sleep(1) # Give worker time to stop
          end

          # Get count before clearing
          stats = app.history.embedding_stats(kind: "man_page")
          count = stats.find { |s| s["kind"] == "man_page" }&.fetch("count", 0) || 0

          # Clear all man_page embeddings
          app.history.clear_embeddings(kind: "man_page")

          # Reset status counters
          app.status_mutex.synchronize do
            app.man_indexer_status["total"] = 0
            app.man_indexer_status["completed"] = 0
            app.man_indexer_status["failed"] = 0
            app.man_indexer_status["skipped"] = 0
            app.man_indexer_status["session_spend"] = 0.0
            app.man_indexer_status["session_tokens"] = 0
          end

          app.output_line("Reset complete: Cleared #{count} man page embeddings", type: :debug)
        end

        def show_invalid_option
          app.console.puts("")
          app.output_line("Invalid option. Use: /index-man <on|off|reset>", type: :debug)
        end
      end
    end
  end
end
