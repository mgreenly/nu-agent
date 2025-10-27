# frozen_string_literal: true

require "spec_helper"
require "nu/agent/help_text_builder"

RSpec.describe Nu::Agent::HelpTextBuilder do
  describe "#build" do
    it "returns help text with all available commands" do
      help_text = described_class.build

      expect(help_text).to include("Available commands:")
      expect(help_text).to include("/clear")
      expect(help_text).to include("/debug <on|off>")
      expect(help_text).to include("/exit")
      expect(help_text).to include("/fix")
      expect(help_text).to include("/help")
      expect(help_text).to include("/index-man <on|off|reset>")
      expect(help_text).to include("/info")
      expect(help_text).to include("/migrate-exchanges")
      expect(help_text).to include("/model orchestrator <name>")
      expect(help_text).to include("/models")
      expect(help_text).to include("/redaction <on|off>")
      expect(help_text).to include("/verbosity <number>")
      expect(help_text).to include("/reset")
      expect(help_text).to include("/spellcheck <on|off>")
      expect(help_text).to include("/summarizer <on|off>")
      expect(help_text).to include("/tools")
    end

    it "returns text split into multiple lines" do
      help_text = described_class.build
      lines = help_text.lines

      expect(lines.size).to be > 20
    end

    it "includes verbosity level descriptions" do
      help_text = described_class.build

      expect(help_text).to include("Level 0:")
      expect(help_text).to include("Level 1:")
      expect(help_text).to include("Level 6:")
    end
  end
end
