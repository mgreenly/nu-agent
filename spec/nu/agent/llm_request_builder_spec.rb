# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::LlmRequestBuilder do
  describe "#initialize" do
    it "creates a new builder instance" do
      builder = described_class.new
      expect(builder).to be_a(described_class)
    end
  end

  describe "#with_system_prompt" do
    it "stores the system prompt and returns self for chaining" do
      builder = described_class.new
      prompt = "You are a helpful assistant"

      result = builder.with_system_prompt(prompt)

      expect(result).to be(builder)
      expect(builder.system_prompt).to eq(prompt)
    end
  end

  describe "#with_history" do
    it "stores the message history and returns self for chaining" do
      builder = described_class.new
      messages = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there!" }
      ]

      result = builder.with_history(messages)

      expect(result).to be(builder)
      expect(builder.history).to eq(messages)
    end
  end
end
