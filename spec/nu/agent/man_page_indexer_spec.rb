# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::ManPageIndexer do
  let(:history) { instance_double(Nu::Agent::History) }
  let(:embeddings_client) { instance_double(Nu::Agent::Clients::OpenAIEmbeddings) }
  let(:application) { instance_double(Nu::Agent::Application) }
  let(:status_mutex) { Mutex.new }
  let(:indexer_status) do
    {
      "running" => false,
      "total" => 0,
      "completed" => 0,
      "failed" => 0,
      "skipped" => 0,
      "current_batch" => nil,
      "session_spend" => 0.0,
      "session_tokens" => 0
    }
  end

  describe "#initialize" do
    it "initializes with required dependencies" do
      indexer = described_class.new(
        history: history,
        embeddings_client: embeddings_client,
        application: application,
        status: indexer_status,
        status_mutex: status_mutex
      )

      expect(indexer).to be_a(described_class)
    end
  end

  describe "#start_worker" do
    let(:indexer) do
      described_class.new(
        history: history,
        embeddings_client: embeddings_client,
        application: application,
        status: indexer_status,
        status_mutex: status_mutex
      )
    end

    it "spawns a background thread" do
      # Mock the indexing process to block indefinitely so thread stays alive
      semaphore = Queue.new
      allow(indexer).to receive(:index_pages) { semaphore.pop }

      thread = indexer.start_worker

      # Give thread time to start
      sleep(0.01)

      expect(thread).to be_a(Thread)
      expect(thread).to be_alive

      # Clean up
      thread.kill
      thread.join
    end
  end

  describe "#index_pages" do
    let(:man_indexer) { instance_double(Nu::Agent::ManIndexer) }
    let(:indexer) do
      described_class.new(
        history: history,
        embeddings_client: embeddings_client,
        application: application,
        status: indexer_status,
        status_mutex: status_mutex
      )
    end

    before do
      # Mock shutdown check
      allow(application).to receive(:instance_variable_get).with(:@shutdown).and_return(false)
      allow(history).to receive(:get_config).with("index_man_enabled").and_return("false")
    end

    it "stops when index_man_enabled is false" do
      allow(Nu::Agent::ManIndexer).to receive(:new).and_return(man_indexer)

      indexer.index_pages

      expect(indexer_status["running"]).to be false
    end

    it "handles empty man page list" do
      allow(Nu::Agent::ManIndexer).to receive(:new).and_return(man_indexer)
      allow(history).to receive(:get_config).with("index_man_enabled").and_return("true")
      allow(man_indexer).to receive(:all_man_pages).and_return([])
      allow(history).to receive(:get_indexed_sources).and_return([])

      indexer.index_pages

      expect(indexer_status["running"]).to be false
      expect(indexer_status["total"]).to eq(0)
    end

    it "processes man pages in batches" do
      allow(Nu::Agent::ManIndexer).to receive(:new).and_return(man_indexer)
      allow(history).to receive(:get_config).with("index_man_enabled").and_return("true", "false")
      allow(man_indexer).to receive(:all_man_pages).and_return(["grep.1", "ls.1"])
      allow(history).to receive(:get_indexed_sources).with(kind: "man_page").and_return([])
      allow(man_indexer).to receive(:extract_description).and_return("test description")
      allow(embeddings_client).to receive(:generate_embedding).and_return({
        "embeddings" => [[0.1, 0.2], [0.3, 0.4]],
        "spend" => 0.001,
        "tokens" => 100
      })
      allow(application).to receive(:send).with(:enter_critical_section)
      allow(application).to receive(:send).with(:exit_critical_section)
      allow(history).to receive(:store_embeddings)

      # Mock sleep to speed up test
      allow(indexer).to receive(:sleep)

      indexer.index_pages

      expect(indexer_status["completed"]).to eq(2)
    end
  end
end
