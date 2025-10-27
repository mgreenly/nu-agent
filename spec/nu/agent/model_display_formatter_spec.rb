# frozen_string_literal: true

require "spec_helper"
require "nu/agent/model_display_formatter"

RSpec.describe Nu::Agent::ModelDisplayFormatter do
  describe ".build" do
    it "returns formatted model list with header" do
      model_text = described_class.build

      expect(model_text).to include("Available Models (* = default):")
    end

    it "includes Anthropic models" do
      model_text = described_class.build

      expect(model_text).to include("Anthropic:")
      expect(model_text).to include("claude")
    end

    it "includes Google models" do
      model_text = described_class.build

      expect(model_text).to include("Google:")
      expect(model_text).to include("gemini")
    end

    it "includes OpenAI models" do
      model_text = described_class.build

      expect(model_text).to include("OpenAI:")
      expect(model_text).to include("gpt")
    end

    it "includes X.AI models" do
      model_text = described_class.build

      expect(model_text).to include("X.AI:")
      expect(model_text).to include("grok")
    end

    it "marks default models with asterisk" do
      model_text = described_class.build

      # Check that some models have asterisks (default markers)
      expect(model_text).to match(/claude-[a-z0-9-]+\*/)
    end

    it "returns multi-line text" do
      model_text = described_class.build
      lines = model_text.lines

      expect(lines.size).to be >= 5
    end
  end
end
