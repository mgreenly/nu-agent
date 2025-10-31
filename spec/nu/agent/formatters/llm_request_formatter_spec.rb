# frozen_string_literal: true

require "spec_helper"
require "nu/agent/formatters/llm_request_formatter"
require "nu/agent/subsystem_debugger"

RSpec.describe Nu::Agent::Formatters::LlmRequestFormatter do
  let(:console) { double("console") }
  let(:history) { double("history") }
  let(:application) { double("application", debug: true, history: history) }
  let(:formatter) { described_class.new(console: console, application: application) }

  let(:messages) do
    [
      { "role" => "user", "content" => "Hello" },
      { "role" => "assistant", "content" => "Hi there!" }
    ]
  end

  describe "#display" do
    context "when debug is false" do
      let(:application) { double("application", debug: false, history: history) }

      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(3)
      end

      it "does not display anything" do
        formatter.display(messages)

        expect(console).not_to have_received(:puts)
      end
    end

    context "when llm_verbosity is less than 3" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(2)
      end

      it "does not display anything" do
        formatter.display(messages)

        expect(console).not_to have_received(:puts)
      end
    end

    context "when debug is true and llm_verbosity >= 3" do
      before do
        allow(console).to receive(:puts)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(3)
      end

      context "without tools" do
        it "displays conversation history" do
          formatter.display(messages)

          expect(console).to have_received(:puts)
            .with("\e[90m--- Conversation History (2 unredacted message(s)) ---\e[0m")
          expect(console).to have_received(:puts).with("\e[90m  Message 1 (role: user)\e[0m")
          expect(console).to have_received(:puts).with("\e[90m  Hello\e[0m")
        end
      end

      context "with tools at llm_verbosity 4+" do
        let(:tools) do
          [
            { "name" => "file_read", "description" => "Read a file" },
            { "name" => "file_write", "description" => "Write a file" }
          ]
        end

        before do
          allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(4)
        end

        it "displays tools section" do
          formatter.display(messages, tools)

          expect(console).to have_received(:puts).with("")
          expect(console).to have_received(:puts).with("\e[90m--- 2 Tools Offered ---\e[0m")
          expect(console).to have_received(:puts).with("\e[90m  - file_read\e[0m")
          expect(console).to have_received(:puts).with("\e[90m  - file_write\e[0m")
        end

        it "handles OpenAI tool format" do
          openai_tools = [
            { "function" => { "name" => "execute_bash" } }
          ]

          formatter.display(messages, openai_tools)

          expect(console).to have_received(:puts).with("\e[90m  - execute_bash\e[0m")
        end
      end

      context "with markdown document" do
        let(:markdown_doc) { "# User Query\n\nWhat is the weather?" }

        it "displays exchange content section" do
          formatter.display(messages, nil, markdown_doc)

          expect(console).to have_received(:puts).with("")
          expect(console).to have_received(:puts).with("\e[90m--- Exchange Content ---\e[0m").twice
          expect(console).to have_received(:puts).with("\e[90m#{markdown_doc}\e[0m")
        end

        it "truncates long markdown documents" do
          long_doc = "a" * 600

          formatter.display(messages, nil, long_doc)

          expect(console).to have_received(:puts).with("\e[90m#{'a' * 500}\e[0m")
          expect(console).to have_received(:puts).with("\e[90m... (600 chars total)\e[0m")
        end

        it "separates history from markdown document" do
          all_messages = messages + [{ "role" => "user", "content" => markdown_doc }]

          formatter.display(all_messages, nil, markdown_doc)

          # Should only show first 2 messages in history section
          expect(console).to have_received(:puts)
            .with("\e[90m--- Conversation History (2 unredacted message(s)) ---\e[0m")
        end
      end

      context "with messages containing tool calls" do
        let(:messages) do
          [
            {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [
                { "name" => "file_read", "arguments" => {} },
                { "name" => "file_write", "arguments" => {} }
              ]
            }
          ]
        end

        it "displays tool call count" do
          formatter.display(messages)

          expect(console).to have_received(:puts).with("\e[90m  [Contains 2 tool call(s)]\e[0m")
        end
      end

      context "with messages containing tool results" do
        let(:messages) do
          [
            {
              "role" => "user",
              "content" => "",
              "tool_result" => {
                "name" => "file_read",
                "result" => "file contents"
              }
            }
          ]
        end

        it "displays tool result name" do
          formatter.display(messages)

          expect(console).to have_received(:puts).with("\e[90m  [Tool result for: file_read]\e[0m")
        end
      end

      context "with long message content" do
        let(:messages) do
          [
            { "role" => "user", "content" => "a" * 250 }
          ]
        end

        it "truncates content preview to 200 chars" do
          formatter.display(messages)

          expect(console).to have_received(:puts).with("\e[90m  #{'a' * 200}\e[0m")
          expect(console).to have_received(:puts).with("\e[90m  ... (250 chars total)\e[0m")
        end
      end
    end

    context "when no application provided" do
      let(:formatter) { described_class.new(console: console, application: nil) }

      before { allow(console).to receive(:puts) }

      it "defaults to llm_verbosity 0 and does not display" do
        formatter.display(messages)

        expect(console).not_to have_received(:puts)
      end
    end
  end
end
