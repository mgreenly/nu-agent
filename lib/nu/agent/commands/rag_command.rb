# frozen_string_literal: true

require_relative "base_command"

module Nu
  module Agent
    module Commands
      # Command to manage RAG retrieval settings and test performance
      class RagCommand < BaseCommand
        def execute(input)
          parts = input.split(" ", 3)
          subcommand = parts[1]&.strip&.downcase
          handle_subcommand(subcommand, parts[2])
          :continue
        end

        def handle_subcommand(subcommand, value)
          case subcommand
          when "status" then show_status
          when "on", "off" then toggle_rag(subcommand)
          when "test" then test_retrieval(value)
          when "conv-limit", "conv-similarity", "exch-per-conv", "exch-cap", "exch-similarity", "token-budget",
               "conv-budget-pct"
            handle_config_update(subcommand, value)
          else
            show_usage
          end
        end

        def handle_config_update(subcommand, value)
          config = config_params(subcommand).merge(value: value)
          update_rag_config(config)
        end

        def config_params(subcommand)
          {
            "conv-limit" => { key: "rag_conversation_limit", display: "Conversation limit", min: 1 },
            "conv-similarity" => { key: "rag_conversation_min_similarity", display: "Conversation min similarity",
                                   min: 0.0, max: 1.0, float: true },
            "exch-per-conv" => { key: "rag_exchanges_per_conversation", display: "Exchanges per conversation", min: 1 },
            "exch-cap" => { key: "rag_exchange_global_cap", display: "Exchange global cap", min: 1 },
            "exch-similarity" => { key: "rag_exchange_min_similarity", display: "Exchange min similarity",
                                   min: 0.0, max: 1.0, float: true },
            "token-budget" => { key: "rag_token_budget", display: "Token budget", min: 100 },
            "conv-budget-pct" => { key: "rag_conversation_budget_pct", display: "Conversation budget percentage",
                                   min: 0.0, max: 1.0, float: true }
          }[subcommand]
        end

        private

        def show_usage
          app.console.puts("")
          usage_lines.each { |line| app.output_line(line, type: :command) }
        end

        def usage_lines
          [
            "Usage: /rag <command>",
            "Commands:",
            "  status                       - Show RAG configuration",
            "  on|off                       - Enable/disable RAG retrieval",
            "  test <query>                 - Test retrieval latency with query",
            "  conv-limit <n>               - Set conversation result limit (default: 5)",
            "  conv-similarity <0.0-1.0>    - Set conversation min similarity (default: 0.7)",
            "  exch-per-conv <n>            - Set exchanges per conversation (default: 3)",
            "  exch-cap <n>                 - Set exchange global cap (default: 10)",
            "  exch-similarity <0.0-1.0>    - Set exchange min similarity (default: 0.6)",
            "  token-budget <n>             - Set token budget (default: 2000)",
            "  conv-budget-pct <0.0-1.0>    - Set conversation budget % (default: 0.4)"
          ]
        end

        def show_status
          app.console.puts("")
          show_rag_status_header
          app.console.puts("")
          show_rag_configuration
        end

        def show_rag_status_header
          enabled = app.history.get_config("rag_enabled", default: "true") == "true"
          vss_available = app.history.get_config("vss_available", default: "false")

          app.output_line("RAG Retrieval Status:", type: :command)
          app.output_line("  Enabled: #{enabled ? 'yes' : 'no'}", type: :command)
          app.output_line("  VSS available: #{vss_available}", type: :command)
        end

        def show_rag_configuration
          app.output_line("Configuration:", type: :command)
          rag_config_lines.each { |line| app.output_line(line, type: :command) }
        end

        def rag_config_lines
          [
            "  Conversation limit: #{get_rag_config('rag_conversation_limit', '5')}",
            "  Conversation min similarity: #{get_rag_config('rag_conversation_min_similarity', '0.7')}",
            "  Exchanges per conversation: #{get_rag_config('rag_exchanges_per_conversation', '3')}",
            "  Exchange global cap: #{get_rag_config('rag_exchange_global_cap', '10')}",
            "  Exchange min similarity: #{get_rag_config('rag_exchange_min_similarity', '0.6')}",
            "  Token budget: #{get_rag_config('rag_token_budget', '2000')}",
            "  Conversation budget %: #{get_rag_config('rag_conversation_budget_pct', '0.4')}"
          ]
        end

        def get_rag_config(key, default)
          app.history.get_config(key, default: default)
        end

        def toggle_rag(setting)
          enabled = setting == "on"
          app.history.set_config("rag_enabled", enabled ? "true" : "false")

          app.console.puts("")
          app.output_line("rag=#{setting}", type: :command)
          if enabled
            app.output_line("RAG retrieval will be used in conversations", type: :command)
          else
            app.output_line("RAG retrieval is disabled", type: :command)
          end
        end

        def test_retrieval(query)
          return show_test_usage if query.nil? || query.empty?
          return show_no_embedding_client_error unless app.embedding_client

          perform_test_retrieval(query)
        end

        def show_test_usage
          app.console.puts("")
          app.output_line("Usage: /rag test <query>", type: :command)
          app.output_line("Example: /rag test How do I configure the database?", type: :command)
        end

        def show_no_embedding_client_error
          app.console.puts("")
          app.output_line("Embedding client not available. Cannot test RAG retrieval.", type: :error)
        end

        def perform_test_retrieval(query)
          app.console.puts("")
          app.output_line("Testing RAG retrieval for: \"#{query}\"", type: :command)
          app.output_line("", type: :command)

          begin
            context = execute_rag_retrieval(query)
            display_rag_results(context)
          rescue StandardError => e
            handle_test_error(e)
          end
        end

        def execute_rag_retrieval(query)
          retriever = create_rag_retriever
          retriever.retrieve(query: query, current_conversation_id: app.conversation_id)
        end

        def create_rag_retriever
          RAG::RAGRetriever.new(
            embedding_store: app.history.instance_variable_get(:@embedding_store),
            embedding_client: app.embedding_client,
            config_store: app.history.instance_variable_get(:@config_store)
          )
        end

        def display_rag_results(context)
          display_rag_metadata(context.metadata)
          app.console.puts("")
          display_rag_context(context.formatted_context)
        end

        def display_rag_metadata(metadata)
          app.output_line("Results:", type: :command)
          app.output_line("  Duration: #{metadata[:duration_ms]}ms", type: :command)
          app.output_line("  Conversations found: #{metadata[:conversation_count]}", type: :command)
          app.output_line("  Exchanges found: #{metadata[:exchange_count]}", type: :command)
          app.output_line("  Estimated tokens: #{metadata[:total_tokens]}", type: :command)
        end

        def display_rag_context(formatted_context)
          if formatted_context && !formatted_context.empty?
            app.output_line("Formatted Context:", type: :command)
            app.console.puts("")
            app.console.puts(formatted_context)
          else
            app.output_line("No relevant context found.", type: :command)
          end
        end

        def handle_test_error(error)
          app.output_line("Error testing RAG retrieval: #{error.message}", type: :error)
          app.output_line(error.backtrace.first, type: :error) if app.debug
        end

        def update_rag_config(options)
          key = options[:key]
          value = options[:value]
          display = options[:display]
          min = options[:min]
          max = options[:max]
          float = options[:float] || false

          return show_current_config(key, display) if value.nil? || value.empty?

          parsed_value = float ? value.to_f : value.to_i
          return show_validation_error(display, min, max, parsed_value) unless valid_range?(parsed_value, min, max)

          save_and_confirm_config(key, value, display, parsed_value)
        end

        def show_current_config(key, display)
          app.console.puts("")
          app.output_line("Current #{display}: #{app.history.get_config(key, default: 'not set')}", type: :command)
        end

        def valid_range?(value, min, max)
          (min.nil? || value >= min) && (max.nil? || value <= max)
        end

        def show_validation_error(display, min, max, value)
          app.console.puts("")
          if min && value < min
            app.output_line("#{display} must be >= #{min}", type: :error)
          elsif max && value > max
            app.output_line("#{display} must be <= #{max}", type: :error)
          else
            # This shouldn't happen with correct usage, but handle it gracefully
            app.output_line("Invalid value for #{display}", type: :error)
          end
        end

        def save_and_confirm_config(key, value, display, parsed_value)
          app.history.set_config(key, value)
          app.console.puts("")
          app.output_line("#{display} set to #{parsed_value}", type: :command)
        end
      end
    end
  end
end
