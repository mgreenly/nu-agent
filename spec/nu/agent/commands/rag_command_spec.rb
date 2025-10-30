# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Commands::RagCommand do
  subject(:command) { described_class.new(app) }

  let(:app) { instance_double("Nu::Agent::Application") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:history) { instance_double("Nu::Agent::History") }

  before do
    allow(app).to receive_messages(console: console, history: history)
    allow(app).to receive(:output_line)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    context "with 'on' subcommand" do
      it "enables RAG retrieval" do
        allow(history).to receive(:set_config)

        command.execute("/rag on")

        expect(history).to have_received(:set_config).with("rag_enabled", "true")
      end
    end

    context "with 'off' subcommand" do
      it "disables RAG retrieval" do
        allow(history).to receive(:set_config)

        command.execute("/rag off")

        expect(history).to have_received(:set_config).with("rag_enabled", "false")
      end
    end

    context "with 'status' subcommand" do
      it "shows RAG configuration" do
        allow(history).to receive(:get_config).and_return("true")

        command.execute("/rag status")

        expect(app).to have_received(:output_line).with(/RAG Retrieval Status:/, type: :command)
        expect(app).to have_received(:output_line).with(/Configuration:/, type: :command)
      end
    end

    context "with configuration subcommands" do
      it "sets conversation limit" do
        allow(history).to receive(:set_config)

        command.execute("/rag conv-limit 10")

        expect(history).to have_received(:set_config).with("rag_conversation_limit", "10")
      end

      it "sets conversation min similarity" do
        allow(history).to receive(:set_config)

        command.execute("/rag conv-similarity 0.8")

        expect(history).to have_received(:set_config).with("rag_conversation_min_similarity", "0.8")
      end

      it "sets token budget" do
        allow(history).to receive(:set_config)

        command.execute("/rag token-budget 3000")

        expect(history).to have_received(:set_config).with("rag_token_budget", "3000")
      end

      it "validates minimum values" do
        command.execute("/rag conv-limit 0")

        expect(app).to have_received(:output_line).with(/must be >= 1/, type: :error)
      end

      it "validates maximum values for percentages" do
        command.execute("/rag conv-budget-pct 1.5")

        expect(app).to have_received(:output_line).with(/must be <= 1.0/, type: :error)
      end
    end

    context "with 'test' subcommand" do
      it "shows usage when no query provided" do
        command.execute("/rag test")

        expect(app).to have_received(:output_line).with(/Usage:/, type: :command)
      end

      it "shows error when embedding client not available" do
        allow(app).to receive(:embedding_client).and_return(nil)

        command.execute("/rag test how do I configure?")

        expect(app).to have_received(:output_line).with(/not available/, type: :error)
      end

      context "with embedding client available" do
        let(:embedding_client) { instance_double("Nu::Agent::Clients::OpenAIEmbeddings") }
        let(:embedding_store) { instance_double("Nu::Agent::EmbeddingStore") }
        let(:config_store) { instance_double("Nu::Agent::ConfigStore") }
        let(:retriever) { instance_double("Nu::Agent::RAG::RAGRetriever") }
        let(:context) do
          instance_double(
            "Nu::Agent::RAG::RAGContext",
            metadata: {
              duration_ms: 150,
              conversation_count: 3,
              exchange_count: 7,
              total_tokens: 850
            },
            formatted_context: "Some relevant context"
          )
        end

        before do
          allow(app).to receive_messages(
            embedding_client: embedding_client,
            conversation_id: 123
          )
          allow(history).to receive(:instance_variable_get).with(:@embedding_store).and_return(embedding_store)
          allow(history).to receive(:instance_variable_get).with(:@config_store).and_return(config_store)
          allow(Nu::Agent::RAG::RAGRetriever).to receive(:new).and_return(retriever)
        end

        it "performs retrieval and displays results" do
          allow(retriever).to receive(:retrieve).and_return(context)

          command.execute("/rag test how do I configure?")

          expect(app).to have_received(:output_line).with(/Testing RAG retrieval/, type: :command)
          expect(app).to have_received(:output_line).with(/Duration: 150ms/, type: :command)
          expect(app).to have_received(:output_line).with(/Conversations found: 3/, type: :command)
          expect(app).to have_received(:output_line).with(/Exchanges found: 7/, type: :command)
          expect(app).to have_received(:output_line).with(/Estimated tokens: 850/, type: :command)
          expect(console).to have_received(:puts).with("Some relevant context")
        end

        it "displays message when no context found" do
          empty_context = instance_double(
            "Nu::Agent::RAG::RAGContext",
            metadata: {
              duration_ms: 100,
              conversation_count: 0,
              exchange_count: 0,
              total_tokens: 0
            },
            formatted_context: ""
          )
          allow(retriever).to receive(:retrieve).and_return(empty_context)

          command.execute("/rag test unknown query")

          expect(app).to have_received(:output_line).with(/No relevant context found/, type: :command)
        end

        it "displays message when context is nil" do
          nil_context = instance_double(
            "Nu::Agent::RAG::RAGContext",
            metadata: {
              duration_ms: 100,
              conversation_count: 0,
              exchange_count: 0,
              total_tokens: 0
            },
            formatted_context: nil
          )
          allow(retriever).to receive(:retrieve).and_return(nil_context)

          command.execute("/rag test unknown query")

          expect(app).to have_received(:output_line).with(/No relevant context found/, type: :command)
        end

        it "handles errors during retrieval" do
          allow(app).to receive(:debug).and_return(false)
          allow(retriever).to receive(:retrieve).and_raise(StandardError.new("Connection failed"))

          command.execute("/rag test error query")

          expect(app).to have_received(:output_line).with(/Error testing RAG retrieval: Connection failed/,
                                                          type: :error)
        end

        it "shows backtrace when debug is enabled" do
          allow(app).to receive(:debug).and_return(true)
          allow(retriever).to receive(:retrieve).and_raise(StandardError.new("Connection failed"))

          command.execute("/rag test error query")

          expect(app).to have_received(:output_line).with(/Error testing RAG retrieval/, type: :error)
          expect(app).to have_received(:output_line).with(anything, type: :error).at_least(2).times
        end
      end
    end

    context "with other configuration subcommands" do
      it "sets exchanges per conversation" do
        allow(history).to receive(:set_config)

        command.execute("/rag exch-per-conv 5")

        expect(history).to have_received(:set_config).with("rag_exchanges_per_conversation", "5")
      end

      it "sets exchange global cap" do
        allow(history).to receive(:set_config)

        command.execute("/rag exch-cap 20")

        expect(history).to have_received(:set_config).with("rag_exchange_global_cap", "20")
      end

      it "sets exchange min similarity" do
        allow(history).to receive(:set_config)

        command.execute("/rag exch-similarity 0.75")

        expect(history).to have_received(:set_config).with("rag_exchange_min_similarity", "0.75")
      end

      it "shows current config when no value provided" do
        allow(history).to receive(:get_config).with("rag_conversation_limit", default: "not set").and_return("5")

        command.execute("/rag conv-limit")

        expect(app).to have_received(:output_line).with(/Current Conversation limit: 5/, type: :command)
      end

      it "validates minimum for similarity values" do
        command.execute("/rag conv-similarity -0.1")

        expect(app).to have_received(:output_line).with(/must be >= 0.0/, type: :error)
      end
    end

    context "with invalid subcommand" do
      it "shows usage" do
        command.execute("/rag invalid")

        expect(app).to have_received(:output_line).with(%r{Usage: /rag <command>}, type: :command)
      end
    end

    context "with no subcommand" do
      it "shows usage" do
        command.execute("/rag")

        expect(app).to have_received(:output_line).with(%r{Usage: /rag <command>}, type: :command)
      end
    end

    context "status display details" do
      it "shows VSS availability status" do
        allow(history).to receive(:get_config) do |key, options|
          if %w[rag_enabled vss_available].include?(key)
            "true"
          else
            options[:default] || "default_value"
          end
        end

        command.execute("/rag status")

        expect(app).to have_received(:output_line).with(/VSS available: true/, type: :command)
      end

      it "shows all configuration parameters" do
        allow(history).to receive(:get_config).and_return("test_value")

        command.execute("/rag status")

        expect(app).to have_received(:output_line).with(/Conversation limit:/, type: :command)
        expect(app).to have_received(:output_line).with(/Conversation min similarity:/, type: :command)
        expect(app).to have_received(:output_line).with(/Exchanges per conversation:/, type: :command)
        expect(app).to have_received(:output_line).with(/Exchange global cap:/, type: :command)
        expect(app).to have_received(:output_line).with(/Exchange min similarity:/, type: :command)
        expect(app).to have_received(:output_line).with(/Token budget:/, type: :command)
        expect(app).to have_received(:output_line).with(/Conversation budget %:/, type: :command)
      end
    end

    context "toggle RAG messages" do
      it "shows enabled message when turning on" do
        allow(history).to receive(:set_config)

        command.execute("/rag on")

        expect(app).to have_received(:output_line).with(/RAG retrieval will be used in conversations/, type: :command)
      end

      it "shows disabled message when turning off" do
        allow(history).to receive(:set_config)

        command.execute("/rag off")

        expect(app).to have_received(:output_line).with(/RAG retrieval is disabled/, type: :command)
      end
    end
  end
end
