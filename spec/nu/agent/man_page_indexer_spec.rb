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
      allow(history).to receive(:get_indexed_sources).with(kind: "man_page").and_return([])
      allow(man_indexer).to receive_messages(all_man_pages: ["grep.1", "ls.1"], extract_description: "test description")
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

    it "skips pages with empty descriptions" do
      allow(Nu::Agent::ManIndexer).to receive(:new).and_return(man_indexer)
      allow(history).to receive(:get_config).with("index_man_enabled").and_return("true", "false")
      allow(history).to receive(:get_indexed_sources).with(kind: "man_page").and_return([])
      allow(man_indexer).to receive(:all_man_pages).and_return(["empty.1"])
      allow(man_indexer).to receive(:extract_description).with("empty.1").and_return(nil)
      allow(indexer).to receive(:sleep)

      indexer.index_pages

      expect(indexer_status["skipped"]).to eq(1)
      expect(indexer_status["completed"]).to eq(0)
    end

    it "handles empty batch with sleep" do
      allow(Nu::Agent::ManIndexer).to receive(:new).and_return(man_indexer)
      allow(history).to receive(:get_config).with("index_man_enabled").and_return("true", "false")
      allow(history).to receive(:get_indexed_sources).with(kind: "man_page").and_return([])
      allow(man_indexer).to receive_messages(all_man_pages: ["empty.1", "empty.2"], extract_description: "")
      allow(indexer).to receive(:sleep)

      indexer.index_pages

      expect(indexer).to have_received(:sleep).with(1).at_least(:once)
    end

    it "handles embeddings API errors" do
      allow(Nu::Agent::ManIndexer).to receive(:new).and_return(man_indexer)

      # Use a counter to stop after first iteration
      call_count = 0
      allow(history).to receive(:get_config).with("index_man_enabled") do
        call_count += 1
        call_count == 1 ? "true" : "false"
      end

      allow(history).to receive(:get_indexed_sources).with(kind: "man_page").and_return([])
      allow(man_indexer).to receive_messages(all_man_pages: ["test.1"], extract_description: "test description")
      allow(embeddings_client).to receive(:generate_embedding).and_return({
                                                                            "error" => {
                                                                              "status" => 500,
                                                                              "body" => {
                                                                                "error" => {
                                                                                  "message" => "Internal server error",
                                                                                  "code" => "server_error"
                                                                                }
                                                                              }
                                                                            }
                                                                          })
      allow(application).to receive(:output_line)
      allow(indexer).to receive(:sleep)

      indexer.index_pages

      expect(indexer_status["failed"]).to eq(1)
      expect(indexer).to have_received(:sleep).with(6).at_least(:once)
    end

    it "handles model_not_found error and stops indexing" do
      allow(Nu::Agent::ManIndexer).to receive(:new).and_return(man_indexer)

      # Use counter to stop loop after first iteration
      call_count = 0
      allow(history).to receive(:get_config).with("index_man_enabled") do
        call_count += 1
        call_count == 1 ? "true" : "false"
      end

      allow(history).to receive(:get_indexed_sources).with(kind: "man_page").and_return([])
      allow(man_indexer).to receive_messages(all_man_pages: ["test.1"], extract_description: "test description")
      allow(embeddings_client).to receive(:generate_embedding).and_return({
                                                                            "error" => {
                                                                              "status" => 404,
                                                                              "body" => {
                                                                                "error" => {
                                                                                  "message" =>
                                                                                    "Model text-embedding-3-small " \
                                                                                    "not found",
                                                                                  "code" => "model_not_found"
                                                                                }
                                                                              }
                                                                            }
                                                                          })
      allow(application).to receive(:output_line)
      allow(indexer).to receive(:sleep)

      indexer.index_pages

      expect(application).to have_received(:output_line).with(
        "[Man Indexer] ERROR: OpenAI API key does not have access to text-embedding-3-small",
        type: :error
      )
      expect(application).to have_received(:output_line).with(
        "  Please enable embeddings API access in your OpenAI project settings",
        type: :error
      )
      expect(application).to have_received(:output_line).with(
        "  Visit: https://platform.openai.com/settings",
        type: :error
      )
      expect(indexer_status["running"]).to be false
    end

    it "handles exceptions during batch processing" do
      allow(Nu::Agent::ManIndexer).to receive(:new).and_return(man_indexer)
      allow(history).to receive(:get_config).with("index_man_enabled").and_return("true", "false")
      allow(history).to receive(:get_indexed_sources).with(kind: "man_page").and_return([])
      allow(man_indexer).to receive_messages(all_man_pages: ["test.1"], extract_description: "test description")
      allow(embeddings_client).to receive(:generate_embedding).and_raise(StandardError.new("Network error"))
      allow(application).to receive(:output_line)
      allow(application).to receive(:instance_variable_get).with(:@debug).and_return(false)
      allow(indexer).to receive(:sleep)

      indexer.index_pages

      expect(indexer_status["failed"]).to eq(1)
      expect(application).to have_received(:output_line).with(
        "[Man Indexer] Error processing batch: StandardError: Network error",
        type: :debug
      )
    end

    it "shows debug backtrace when debug mode is enabled" do
      allow(Nu::Agent::ManIndexer).to receive(:new).and_return(man_indexer)
      allow(history).to receive(:get_config).with("index_man_enabled").and_return("true", "false")
      allow(history).to receive(:get_indexed_sources).with(kind: "man_page").and_return([])
      allow(man_indexer).to receive_messages(all_man_pages: ["test.1"], extract_description: "test description")

      error = StandardError.new("Network error")
      allow(error).to receive(:backtrace).and_return(%w[line1 line2 line3 line4 line5])
      allow(embeddings_client).to receive(:generate_embedding).and_raise(error)
      allow(application).to receive(:output_line)
      allow(application).to receive(:instance_variable_get).with(:@debug).and_return(true)
      allow(application).to receive(:instance_variable_get).with(:@shutdown).and_return(false)
      allow(indexer).to receive(:sleep)

      indexer.index_pages

      expect(application).to have_received(:output_line).with(
        "[Man Indexer] Error processing batch: StandardError: Network error",
        type: :debug
      )
      expect(application).to have_received(:output_line).with("  line1", type: :debug)
      expect(application).to have_received(:output_line).with("  line2", type: :debug)
    end
  end

  describe "#start_worker error handling" do
    let(:indexer) do
      described_class.new(
        history: history,
        embeddings_client: embeddings_client,
        application: application,
        status: indexer_status,
        status_mutex: status_mutex
      )
    end

    it "handles exceptions in worker thread" do
      allow(indexer).to receive(:index_pages).and_raise(StandardError.new("Worker crashed"))
      allow(application).to receive(:output_line)
      allow(application).to receive(:instance_variable_get).with(:@debug).and_return(false)

      thread = indexer.start_worker
      sleep(0.05) # Give thread time to crash

      expect(application).to have_received(:output_line).with(
        "[Man Indexer] Worker thread error: StandardError: Worker crashed",
        type: :error
      )
      expect(indexer_status["running"]).to be false

      thread.join(1) # Clean up
    end

    it "shows debug backtrace when worker crashes with debug mode" do
      error = StandardError.new("Worker crashed")
      allow(error).to receive(:backtrace).and_return(
        Array.new(15) { |i| "backtrace line #{i}" }
      )

      allow(indexer).to receive(:index_pages).and_raise(error)
      allow(application).to receive(:output_line)
      allow(application).to receive(:instance_variable_get).with(:@debug).and_return(true)

      thread = indexer.start_worker
      sleep(0.05)

      expect(application).to have_received(:output_line).with(
        "[Man Indexer] Worker thread error: StandardError: Worker crashed",
        type: :error
      )

      # Should show first 10 lines of backtrace
      (0..9).each do |i|
        expect(application).to have_received(:output_line).with(
          "  backtrace line #{i}",
          type: :debug
        )
      end

      # Should NOT show lines 10-14
      (10..14).each do |i|
        expect(application).not_to have_received(:output_line).with(
          "  backtrace line #{i}",
          type: :debug
        )
      end

      thread.join(1)
    end
  end
end
