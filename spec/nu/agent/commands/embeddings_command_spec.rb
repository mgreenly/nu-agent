# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Commands::EmbeddingsCommand do
  subject(:command) { described_class.new(app) }

  let(:app) { instance_double("Nu::Agent::Application") }
  let(:console) { instance_double("Nu::Agent::ConsoleIO") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:worker_manager) { instance_double("Nu::Agent::BackgroundWorkerManager") }
  let(:embedding_status) do
    {
      "running" => false,
      "total" => 0,
      "completed" => 0,
      "failed" => 0,
      "current_item" => nil,
      "spend" => 0.0
    }
  end

  before do
    allow(app).to receive(:output_line)
    allow(app).to receive(:embedding_enabled=)
    allow(app).to receive_messages(console: console, history: history, embedding_enabled: true,
                                   embedding_status: embedding_status,
                                   embedding_client: double("embedding_client"), worker_manager: worker_manager)
    allow(console).to receive(:puts)
  end

  describe "#execute" do
    context "with 'on' subcommand" do
      it "enables embeddings" do
        allow(history).to receive(:set_config)

        command.execute("/embeddings on")

        expect(app).to have_received(:embedding_enabled=).with(true)
        expect(history).to have_received(:set_config).with("embedding_enabled", "true")
      end
    end

    context "with 'off' subcommand" do
      it "disables embeddings" do
        allow(history).to receive(:set_config)

        command.execute("/embeddings off")

        expect(app).to have_received(:embedding_enabled=).with(false)
        expect(history).to have_received(:set_config).with("embedding_enabled", "false")
      end
    end

    context "with 'status' subcommand" do
      it "shows worker status" do
        allow(history).to receive(:get_config).and_return("10")

        command.execute("/embeddings status")

        expect(app).to have_received(:output_line).with(/Enabled:/, type: :debug)
        expect(app).to have_received(:output_line).with(/Running:/, type: :debug)
      end
    end

    context "with 'batch' subcommand" do
      it "sets batch size" do
        allow(history).to receive(:set_config)

        command.execute("/embeddings batch 20")

        expect(history).to have_received(:set_config).with("embedding_batch_size", "20")
      end
    end

    context "with 'rate' subcommand" do
      it "sets rate limit" do
        allow(history).to receive(:set_config)

        command.execute("/embeddings rate 200")

        expect(history).to have_received(:set_config).with("embedding_rate_limit_ms", "200")
      end
    end

    context "with 'start' subcommand" do
      it "starts the worker" do
        allow(worker_manager).to receive(:start_embedding_worker)

        command.execute("/embeddings start")

        expect(worker_manager).to have_received(:start_embedding_worker)
      end

      it "shows error if embeddings disabled" do
        allow(app).to receive(:embedding_enabled).and_return(false)

        command.execute("/embeddings start")

        expect(app).to have_received(:output_line).with(/disabled/, type: :error)
      end
    end
  end
end
