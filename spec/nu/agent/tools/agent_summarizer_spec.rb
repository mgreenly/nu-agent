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
      end
    end
  end
end
