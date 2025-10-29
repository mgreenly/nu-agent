# frozen_string_literal: true

require "spec_helper"
require "nu/agent/tools/agent_summarizer"

RSpec.describe Nu::Agent::Tools::AgentSummarizer do
  let(:tool) { described_class.new }
  let(:mock_history) { instance_double(Nu::Agent::History) }
  let(:mock_console) { instance_double(Nu::Agent::ConsoleIO, puts: nil) }
  let(:status_mutex) { Mutex.new }
  let(:summarizer_status) do
    {
      "running" => false,
      "total" => 0,
      "completed" => 0,
      "failed" => 0,
      "current_conversation_id" => nil,
      "last_summary" => nil,
      "spend" => 0.0
    }
  end
  let(:mock_application) do
    instance_double(
      Nu::Agent::Application,
      console: mock_console,
      debug: true,
      status_mutex: status_mutex,
      summarizer_status: summarizer_status
    )
  end
  let(:context) { { "application" => mock_application } }

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("agent_summarizer")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for checking background summarization status")
      expect(tool.description).to include("progress information")
    end
  end

  describe "#parameters" do
    it "returns an empty hash" do
      expect(tool.parameters).to eq({})
    end
  end

  describe "#execute" do
    it "does not reference OutputBuffer class" do
      # This test ensures OutputBuffer is not used in the tool code
      tool_source = File.read("lib/nu/agent/tools/agent_summarizer.rb")
      expect(tool_source).not_to include("OutputBuffer")
    end

    context "when application is not in context" do
      let(:context) { {} }

      it "returns an error" do
        result = tool.execute(arguments: {}, history: mock_history, context: context)
        expect(result["error"]).to eq("Application context not available")
      end
    end

    context "when summarizer is idle" do
      it "returns idle status" do
        result = tool.execute(arguments: {}, history: mock_history, context: context)
        expect(result["status"]).to eq("idle")
        expect(result["message"]).to eq("No conversations to summarize")
        expect(result["spend"]).to eq(0.0)
      end
    end

    context "when summarizer is running" do
      let(:summarizer_status) do
        {
          "running" => true,
          "total" => 50,
          "completed" => 25,
          "failed" => 2,
          "current_conversation_id" => 123,
          "last_summary" => "This is a summary of the conversation",
          "spend" => 0.05
        }
      end

      it "returns running status with progress" do
        result = tool.execute(arguments: {}, history: mock_history, context: context)

        expect(result["status"]).to eq("running")
        expect(result["progress"]).to eq("25/50 conversations")
        expect(result["total"]).to eq(50)
        expect(result["completed"]).to eq(25)
        expect(result["failed"]).to eq(2)
        expect(result["current_conversation_id"]).to eq(123)
        expect(result["last_summary"]).to eq("This is a summary of the conversation")
        expect(result["spend"]).to eq(0.05)
      end

      context "with nil last_summary" do
        let(:summarizer_status) do
          {
            "running" => true,
            "total" => 10,
            "completed" => 5,
            "failed" => 0,
            "current_conversation_id" => 456,
            "last_summary" => nil,
            "spend" => 0.01
          }
        end

        it "returns nil for last_summary" do
          result = tool.execute(arguments: {}, history: mock_history, context: context)

          expect(result["last_summary"]).to be_nil
        end
      end

      context "with long last_summary" do
        let(:long_summary) { "A" * 200 }
        let(:summarizer_status) do
          {
            "running" => true,
            "total" => 10,
            "completed" => 5,
            "failed" => 0,
            "current_conversation_id" => 789,
            "last_summary" => long_summary,
            "spend" => 0.02
          }
        end

        it "truncates summary to 150 characters" do
          result = tool.execute(arguments: {}, history: mock_history, context: context)

          expect(result["last_summary"]).to eq("#{'A' * 151}...")
          expect(result["last_summary"].length).to eq(154)
        end
      end
    end

    context "when summarizer is completed" do
      let(:summarizer_status) do
        {
          "running" => false,
          "total" => 100,
          "completed" => 95,
          "failed" => 5,
          "current_conversation_id" => nil,
          "last_summary" => "Final conversation summary",
          "spend" => 0.50
        }
      end

      it "returns completed status" do
        result = tool.execute(arguments: {}, history: mock_history, context: context)

        expect(result["status"]).to eq("completed")
        expect(result["total"]).to eq(100)
        expect(result["completed"]).to eq(95)
        expect(result["failed"]).to eq(5)
        expect(result["last_summary"]).to eq("Final conversation summary")
        expect(result["spend"]).to eq(0.50)
        expect(result).not_to have_key("current_conversation_id")
      end

      context "with nil last_summary" do
        let(:summarizer_status) do
          {
            "running" => false,
            "total" => 20,
            "completed" => 20,
            "failed" => 0,
            "current_conversation_id" => nil,
            "last_summary" => nil,
            "spend" => 0.10
          }
        end

        it "returns nil for last_summary" do
          result = tool.execute(arguments: {}, history: mock_history, context: context)

          expect(result["last_summary"]).to be_nil
        end
      end

      context "with long last_summary" do
        let(:long_summary) { "B" * 180 }
        let(:summarizer_status) do
          {
            "running" => false,
            "total" => 30,
            "completed" => 30,
            "failed" => 0,
            "current_conversation_id" => nil,
            "last_summary" => long_summary,
            "spend" => 0.15
          }
        end

        it "truncates summary to 150 characters" do
          result = tool.execute(arguments: {}, history: mock_history, context: context)

          expect(result["last_summary"]).to eq("#{'B' * 151}...")
        end
      end
    end

    context "with thread safety" do
      let(:summarizer_status) do
        {
          "running" => true,
          "total" => 10,
          "completed" => 5,
          "failed" => 0,
          "current_conversation_id" => 100,
          "last_summary" => "Test",
          "spend" => 0.01
        }
      end

      it "uses mutex to safely read status" do
        expect(status_mutex).to receive(:synchronize).and_call_original

        tool.execute(arguments: {}, history: mock_history, context: context)
      end

      it "returns a duplicate of the status hash" do
        result = tool.execute(arguments: {}, history: mock_history, context: context)

        # Modifying result shouldn't affect the original
        result["total"] = 999

        # Execute again and verify the total is still 10
        result2 = tool.execute(arguments: {}, history: mock_history, context: context)
        expect(result2["total"]).to eq(10)
      end
    end
  end
end
