# frozen_string_literal: true

require "spec_helper"
require "nu/agent/session_info"

RSpec.describe Nu::Agent::SessionInfo do
  let(:orchestrator) { double("orchestrator", model: "claude-sonnet-4-5") }
  let(:spellchecker) { double("spellchecker", model: "claude-haiku-4-5") }
  let(:summarizer) { double("summarizer", model: "claude-haiku-4-5") }
  let(:history) { double("history", db_path: "/tmp/test.db") }
  let(:summarizer_status) do
    { "running" => false, "completed" => 0, "total" => 0, "failed" => 0, "spend" => 0.0 }
  end
  let(:status_mutex) { Mutex.new }

  let(:application) do
    double("application",
           orchestrator: orchestrator,
           spellchecker: spellchecker,
           summarizer: summarizer,
           history: history,
           debug: true,
           verbosity: 2,
           redact: false,
           summarizer_enabled: false,
           summarizer_status: summarizer_status,
           status_mutex: status_mutex,
           spell_check_enabled: true)
  end

  describe ".build" do
    it "returns session info text with version" do
      info_text = described_class.build(application)

      expect(info_text).to include("Version:")
      expect(info_text).to include(Nu::Agent::VERSION)
    end

    it "includes model information" do
      info_text = described_class.build(application)

      expect(info_text).to include("Models:")
      expect(info_text).to include("Orchestrator:")
      expect(info_text).to include("claude-sonnet-4-5")
      expect(info_text).to include("Spellchecker:")
      expect(info_text).to include("Summarizer:")
    end

    it "includes debug settings" do
      info_text = described_class.build(application)

      expect(info_text).to include("Debug mode:")
      expect(info_text).to include("Verbosity:")
      expect(info_text).to include("Redaction:")
    end

    it "shows redaction as on when enabled" do
      allow(application).to receive(:redact).and_return(true)
      info_text = described_class.build(application)

      expect(info_text).to include("Redaction:     on")
    end

    it "includes summarizer status when enabled" do
      allow(application).to receive(:summarizer_enabled).and_return(true)
      info_text = described_class.build(application)

      expect(info_text).to include("Summarizer:")
      expect(info_text).to include("Status:")
    end

    it "shows running status for summarizer" do
      allow(application).to receive_messages(
        summarizer_enabled: true,
        summarizer_status: {
          "running" => true, "completed" => 5, "total" => 10,
          "failed" => 0, "spend" => 0.001
        }
      )

      info_text = described_class.build(application)

      expect(info_text).to include("running")
      expect(info_text).to include("5/10")
    end

    it "shows completed status for summarizer" do
      allow(application).to receive_messages(
        summarizer_enabled: true,
        summarizer_status: {
          "running" => false, "completed" => 10, "total" => 10,
          "failed" => 1, "spend" => 0.005
        }
      )

      info_text = described_class.build(application)

      expect(info_text).to include("completed")
      expect(info_text).to include("10/10")
      expect(info_text).to include("1 failed")
    end

    it "includes spellcheck status" do
      info_text = described_class.build(application)

      expect(info_text).to include("Spellcheck:")
    end

    it "includes database path" do
      info_text = described_class.build(application)

      expect(info_text).to include("Database:")
      expect(info_text).to include("/tmp/test.db")
    end
  end
end
