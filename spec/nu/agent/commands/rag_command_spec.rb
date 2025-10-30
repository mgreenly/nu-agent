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

        expect(app).to have_received(:output_line).with(/RAG Retrieval Status:/, type: :debug)
        expect(app).to have_received(:output_line).with(/Configuration:/, type: :debug)
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

        expect(app).to have_received(:output_line).with(/Usage:/, type: :debug)
      end

      it "shows error when embedding client not available" do
        allow(app).to receive(:embedding_client).and_return(nil)

        command.execute("/rag test how do I configure?")

        expect(app).to have_received(:output_line).with(/not available/, type: :error)
      end
    end
  end
end
