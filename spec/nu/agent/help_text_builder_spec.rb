# frozen_string_literal: true

require "spec_helper"
require "nu/agent/help_text_builder"

RSpec.describe Nu::Agent::HelpTextBuilder do
  describe "#build" do
    let(:help_text) { described_class.build }

    it "returns help text with available commands section" do
      expect(help_text).to include("Available commands:")
      expect(help_text).to include("/clear")
      expect(help_text).to include("/debug <on|off>")
      expect(help_text).to include("/exit")
      expect(help_text).to include("/fix")
      expect(help_text).to include("/help")
      expect(help_text).to include("/index-man <on|off|reset>")
      expect(help_text).to include("/info")
      expect(help_text).to include("/migrate-exchanges")
    end

    it "includes model and configuration commands" do
      expect(help_text).to include("/model orchestrator <name>")
      expect(help_text).to include("/models")
      expect(help_text).to include("/redaction <on|off>")
      expect(help_text).to include("/reset")
      expect(help_text).to include("/summarizer <on|off>")
      expect(help_text).to include("/tools")
    end

    it "includes subsystem commands" do
      expect(help_text).to include("/llm")
      expect(help_text).to include("/tools")
      expect(help_text).to include("/messages")
      expect(help_text).to include("/search")
      expect(help_text).to include("/stats")
    end

    it "returns text split into multiple lines" do
      lines = help_text.lines

      expect(lines.size).to be > 20
    end

    it "includes debug subsystems section" do
      expect(help_text).to include("Debug Subsystems:")
      expect(help_text).to include("Use /<subsystem> help for details")
    end
  end
end
