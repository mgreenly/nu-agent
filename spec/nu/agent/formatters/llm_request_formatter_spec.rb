# frozen_string_literal: true

require "spec_helper"
require "nu/agent/formatters/llm_request_formatter"
require "nu/agent/subsystem_debugger"

RSpec.describe Nu::Agent::Formatters::LlmRequestFormatter do
  let(:console) { double("console") }
  let(:history) { double("history") }
  let(:application) { double("application", debug: true, history: history) }
  let(:formatter) { described_class.new(console: console, application: application) }

  let(:internal_request) do
    {
      system_prompt: "You are a helpful assistant.",
      messages: [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there!" },
        { role: "user", content: "How are you?" }
      ],
      tools: [
        { name: "file_read", description: "Read a file" },
        { name: "file_write", description: "Write a file" }
      ],
      metadata: {
        rag_content: { redactions: ["secret"], spell_check: [] },
        user_query: "How are you?",
        conversation_id: 123,
        exchange_id: 456
      }
    }
  end

  describe "#display_yaml" do
    context "with verbosity level 0" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(0)
      end

      it "displays nothing" do
        formatter.display_yaml(internal_request)

        expect(console).not_to have_received(:puts)
      end
    end

    context "with verbosity level 1" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(1)
      end

      it "displays only the final user message in YAML format" do
        formatter.display_yaml(internal_request)

        # Expect to see YAML header
        expect(console).to have_received(:puts).with("\e[90m--- LLM Request ---\e[0m")

        # Expect to see the final message in YAML format
        expect(console).to have_received(:puts).with(
          a_string_matching(/role: user/)
        )
        expect(console).to have_received(:puts).with(
          a_string_matching(/content: How are you\?/)
        )

        # Should NOT see system_prompt, tools, or metadata keys
        expect(console).not_to have_received(:puts).with(
          a_string_matching(/system_prompt:/)
        )
        expect(console).not_to have_received(:puts).with(
          a_string_matching(/tools:/)
        )
        expect(console).not_to have_received(:puts).with(
          a_string_matching(/metadata:/)
        )
      end
    end
  end

  # Old tests will be removed in Task 3.5
end
