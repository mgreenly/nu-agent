# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Tools::ManIndexer do
  let(:tool) { described_class.new }
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }
  let(:status_mutex) { Mutex.new }

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("man_indexer")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("man page indexing")
      expect(tool.description).to include("progress information")
    end
  end

  describe "#parameters" do
    it "returns an empty hash" do
      expect(tool.parameters).to eq({})
    end
  end

  describe "#execute" do
    let(:context) { { "application" => application, "history" => history } }

    before do
      allow(application).to receive(:status_mutex).and_return(status_mutex)
    end

    context "when application context is not available" do
      it "returns error response" do
        result = tool.execute(context: { "history" => history })

        expect(result["error"]).to eq("Application context not available")
      end
    end

    context "when indexing is enabled" do
      before do
        allow(history).to receive(:get_config).with("index_man_enabled").and_return("true")
      end

      context "when indexing is running" do
        let(:man_indexer_status) do
          {
            "running" => true,
            "total" => 100,
            "completed" => 30,
            "failed" => 5,
            "skipped" => 2,
            "current_batch" => %w[man1 man2 man3],
            "session_spend" => 0.05,
            "session_tokens" => 1000
          }
        end

        before do
          allow(application).to receive(:man_indexer_status).and_return(man_indexer_status)
        end

        it "returns running status with progress and current batch" do
          result = tool.execute(context: context)

          expect(result["enabled"]).to be true
          expect(result["running"]).to be true
          expect(result["progress"]["total"]).to eq(100)
          expect(result["progress"]["completed"]).to eq(30)
          expect(result["progress"]["failed"]).to eq(5)
          expect(result["progress"]["skipped"]).to eq(2)
          expect(result["progress"]["remaining"]).to eq(70)
          expect(result["session"]["spend"]).to eq(0.05)
          expect(result["session"]["tokens"]).to eq(1000)
          expect(result["current_batch"]).to eq(%w[man1 man2 man3])
        end
      end

      context "when indexing is completed" do
        let(:man_indexer_status) do
          {
            "running" => false,
            "total" => 100,
            "completed" => 100,
            "failed" => 0,
            "skipped" => 0,
            "session_spend" => 0.10,
            "session_tokens" => 2000
          }
        end

        before do
          allow(application).to receive(:man_indexer_status).and_return(man_indexer_status)
        end

        it "returns completed status without current batch" do
          result = tool.execute(context: context)

          expect(result["enabled"]).to be true
          expect(result["running"]).to be false
          expect(result["progress"]["total"]).to eq(100)
          expect(result["progress"]["completed"]).to eq(100)
          expect(result["progress"]["remaining"]).to eq(0)
          expect(result["session"]["spend"]).to eq(0.10)
          expect(result["session"]["tokens"]).to eq(2000)
          expect(result).not_to have_key("current_batch")
        end
      end

      context "when indexing has not started" do
        let(:man_indexer_status) do
          {
            "running" => false,
            "total" => 0,
            "completed" => 0,
            "failed" => 0,
            "skipped" => 0,
            "session_spend" => 0.0,
            "session_tokens" => 0
          }
        end

        before do
          allow(application).to receive(:man_indexer_status).and_return(man_indexer_status)
        end

        it "returns idle status with message" do
          result = tool.execute(context: context)

          expect(result["enabled"]).to be true
          expect(result["running"]).to be false
          expect(result["message"]).to eq("Man page indexing not yet started")
          expect(result).not_to have_key("progress")
        end
      end
    end

    context "when indexing is disabled" do
      before do
        allow(history).to receive(:get_config).with("index_man_enabled").and_return("false")
        allow(application).to receive(:man_indexer_status).and_return(man_indexer_status)
      end

      let(:man_indexer_status) do
        {
          "running" => false,
          "total" => 0,
          "completed" => 0,
          "failed" => 0,
          "skipped" => 0,
          "session_spend" => 0.0,
          "session_tokens" => 0
        }
      end

      it "returns disabled status" do
        result = tool.execute(context: context)

        expect(result["enabled"]).to be false
      end
    end

    context "when config returns nil" do
      before do
        allow(history).to receive(:get_config).with("index_man_enabled").and_return(nil)
        allow(application).to receive(:man_indexer_status).and_return(man_indexer_status)
      end

      let(:man_indexer_status) do
        {
          "running" => false,
          "total" => 0,
          "completed" => 0,
          "failed" => 0,
          "skipped" => 0,
          "session_spend" => 0.0,
          "session_tokens" => 0
        }
      end

      it "treats nil as disabled" do
        result = tool.execute(context: context)

        expect(result["enabled"]).to be false
      end
    end

    context "with thread safety" do
      let(:man_indexer_status) do
        {
          "running" => true,
          "total" => 50,
          "completed" => 25,
          "failed" => 0,
          "skipped" => 0,
          "current_batch" => ["test"],
          "session_spend" => 0.01,
          "session_tokens" => 100
        }
      end

      before do
        allow(history).to receive(:get_config).with("index_man_enabled").and_return("true")
        allow(application).to receive(:man_indexer_status).and_return(man_indexer_status)
      end

      it "uses mutex to safely read status" do
        expect(status_mutex).to receive(:synchronize).and_call_original

        tool.execute(context: context)
      end

      it "returns a duplicate of the status hash" do
        result = tool.execute(context: context)

        # Modifying result shouldn't affect the original
        result["progress"]["total"] = 999

        # Execute again and verify the total is still 50
        result2 = tool.execute(context: context)
        expect(result2["progress"]["total"]).to eq(50)
      end
    end
  end
end
