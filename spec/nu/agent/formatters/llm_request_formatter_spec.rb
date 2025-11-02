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

        # Expect to see YAML header with blank line before it
        expect(console).to have_received(:puts).with("").ordered
        expect(console).to have_received(:puts).with("\e[90m--- LLM Request ---\e[0m").ordered

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

      it "does not display YAML document marker in output" do
        formatter.display_yaml(internal_request)

        # Should NOT see YAML document marker "---" in the YAML content
        # The header contains "--- LLM Request ---" but that's different
        # We're checking that YAML.dump's "---\n" marker is not present
        expect(console).not_to have_received(:puts).with("\e[90m---\e[0m")
      end
    end

    context "with verbosity level 2" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(2)
      end

      it "displays final message and system_prompt" do
        formatter.display_yaml(internal_request)

        # Should see final message
        expect(console).to have_received(:puts).with(
          a_string_matching(/final_message:/)
        )

        # Should see system_prompt
        expect(console).to have_received(:puts).with(
          a_string_matching(/system_prompt:/)
        )
        expect(console).to have_received(:puts).with(
          a_string_matching(/You are a helpful assistant/)
        )

        # Should NOT see tools or rag_content yet
        expect(console).not_to have_received(:puts).with(
          a_string_matching(/tools:/)
        )
        expect(console).not_to have_received(:puts).with(
          a_string_matching(/rag_content:/)
        )
      end
    end

    context "with verbosity level 3" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(3)
      end

      it "displays final message, system_prompt, and rag_content" do
        formatter.display_yaml(internal_request)

        # Should see final message and system_prompt
        expect(console).to have_received(:puts).with(
          a_string_matching(/final_message:/)
        )
        expect(console).to have_received(:puts).with(
          a_string_matching(/system_prompt:/)
        )

        # Should see rag_content
        expect(console).to have_received(:puts).with(
          a_string_matching(/rag_content:/)
        )
        expect(console).to have_received(:puts).with(
          a_string_matching(/redactions:/)
        )

        # Should NOT see tools or full messages yet
        expect(console).not_to have_received(:puts).with(
          a_string_matching(/tools:/)
        )
        expect(console).not_to have_received(:puts).with(
          a_string_matching(/messages:/)
        )
      end
    end

    context "with verbosity level 4" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(4)
      end

      it "displays final message, system_prompt, rag_content, and tools" do
        formatter.display_yaml(internal_request)

        # Should see final message, system_prompt, and rag_content
        expect(console).to have_received(:puts).with(
          a_string_matching(/final_message:/)
        )
        expect(console).to have_received(:puts).with(
          a_string_matching(/system_prompt:/)
        )
        expect(console).to have_received(:puts).with(
          a_string_matching(/rag_content:/)
        )

        # Should see tools
        expect(console).to have_received(:puts).with(
          a_string_matching(/tools:/)
        )
        expect(console).to have_received(:puts).with(
          a_string_matching(/file_read/)
        )

        # Should NOT see full messages yet
        expect(console).not_to have_received(:puts).with(
          a_string_matching(/messages:/)
        )
      end
    end

    context "with verbosity level 5" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(5)
      end

      it "displays everything including full message history" do
        formatter.display_yaml(internal_request)

        # Should see everything including full messages
        expect(console).to have_received(:puts).with(
          a_string_matching(/messages:/)
        )
        expect(console).to have_received(:puts).with(
          a_string_matching(/system_prompt:/)
        )
        expect(console).to have_received(:puts).with(
          a_string_matching(/rag_content:/)
        )
        expect(console).to have_received(:puts).with(
          a_string_matching(/tools:/)
        )

        # Should see all messages in history
        expect(console).to have_received(:puts).with(
          a_string_matching(/Hello/)
        )
        expect(console).to have_received(:puts).with(
          a_string_matching(/Hi there!/)
        )
      end
    end
  end

  # Old tests will be removed in Task 3.5
end
