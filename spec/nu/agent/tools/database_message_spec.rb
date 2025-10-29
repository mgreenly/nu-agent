# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Tools::DatabaseMessage do
  let(:tool) { described_class.new }
  let(:history) { instance_double("History") }
  let(:context) { { "conversation_id" => 123, "application" => "test_app" } }

  describe "#name" do
    it "returns the tool name" do
      expect(tool.name).to eq("database_message")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to include("PREFERRED tool for retrieving specific messages")
    end

    it "mentions retrieving by ID" do
      expect(tool.description).to include("messages by ID")
    end

    it "mentions conversation history" do
      expect(tool.description).to include("conversation history")
    end
  end

  describe "#parameters" do
    it "defines expected parameters" do
      params = tool.parameters

      expect(params).to have_key(:message_id)
    end

    it "marks message_id as required" do
      expect(tool.parameters[:message_id][:required]).to be true
    end
  end

  describe "#execute" do
    context "with missing message_id parameter" do
      it "returns error when message_id is nil" do
        result = tool.execute(arguments: {}, history: history, context: context)

        expect(result[:error]).to eq("message_id is required")
      end
    end

    context "with string keys in arguments" do
      let(:message) do
        {
          "id" => 1,
          "role" => "user",
          "created_at" => "2024-01-01 10:00:00",
          "content" => "test message"
        }
      end

      before do
        allow(history).to receive(:get_message_by_id).with(1, conversation_id: 123).and_return(message)
      end

      it "accepts string keys for message_id" do
        result = tool.execute(arguments: { "message_id" => 1 }, history: history, context: context)

        expect(result["message_id"]).to eq(1)
      end
    end

    context "when message is found" do
      let(:message) do
        {
          "id" => 42,
          "role" => "assistant",
          "created_at" => "2024-01-01 12:00:00",
          "content" => "Hello, world!"
        }
      end

      before do
        allow(history).to receive(:get_message_by_id).with(42, conversation_id: 123).and_return(message)
      end

      it "returns message_id" do
        result = tool.execute(arguments: { message_id: 42 }, history: history, context: context)

        expect(result["message_id"]).to eq(42)
      end

      it "returns role" do
        result = tool.execute(arguments: { message_id: 42 }, history: history, context: context)

        expect(result["role"]).to eq("assistant")
      end

      it "returns timestamp" do
        result = tool.execute(arguments: { message_id: 42 }, history: history, context: context)

        expect(result["timestamp"]).to eq("2024-01-01 12:00:00")
      end

      it "returns content when present" do
        result = tool.execute(arguments: { message_id: 42 }, history: history, context: context)

        expect(result["message_content"]).to eq("Hello, world!")
      end

      it "calls history.get_message_by_id with correct parameters" do
        expect(history).to receive(:get_message_by_id).with(42, conversation_id: 123)

        tool.execute(arguments: { message_id: 42 }, history: history, context: context)
      end
    end

    context "when message has no content" do
      let(:message_without_content) do
        {
          "id" => 1,
          "role" => "user",
          "created_at" => "2024-01-01 10:00:00",
          "content" => ""
        }
      end

      before do
        allow(history).to receive(:get_message_by_id).and_return(message_without_content)
      end

      it "does not include message_content field when content is empty" do
        result = tool.execute(arguments: { message_id: 1 }, history: history, context: context)

        expect(result).not_to have_key("message_content")
      end
    end

    context "when message has nil content" do
      let(:message_nil_content) do
        {
          "id" => 1,
          "role" => "user",
          "created_at" => "2024-01-01 10:00:00",
          "content" => nil
        }
      end

      before do
        allow(history).to receive(:get_message_by_id).and_return(message_nil_content)
      end

      it "does not include message_content field when content is nil" do
        result = tool.execute(arguments: { message_id: 1 }, history: history, context: context)

        expect(result).not_to have_key("message_content")
      end
    end

    context "when message has tool_calls" do
      let(:message_with_tool_calls) do
        {
          "id" => 2,
          "role" => "assistant",
          "created_at" => "2024-01-01 11:00:00",
          "tool_calls" => [
            { "name" => "file_read", "arguments" => { "path" => "/test" } },
            { "name" => "file_write", "arguments" => { "path" => "/output", "content" => "data" } }
          ]
        }
      end

      before do
        allow(history).to receive(:get_message_by_id).and_return(message_with_tool_calls)
      end

      it "includes formatted tool_calls" do
        result = tool.execute(arguments: { message_id: 2 }, history: history, context: context)

        expect(result["tool_calls"]).to be_an(Array)
        expect(result["tool_calls"].length).to eq(2)
      end

      it "formats each tool call with tool_name and arguments" do
        result = tool.execute(arguments: { message_id: 2 }, history: history, context: context)

        first_call = result["tool_calls"][0]
        expect(first_call["tool_name"]).to eq("file_read")
        expect(first_call["arguments"]).to eq({ "path" => "/test" })
      end
    end

    context "when message has tool_result" do
      let(:message_with_tool_result) do
        {
          "id" => 3,
          "role" => "tool",
          "created_at" => "2024-01-01 11:30:00",
          "tool_result" => {
            "name" => "file_read",
            "result" => "File contents here"
          }
        }
      end

      before do
        allow(history).to receive(:get_message_by_id).and_return(message_with_tool_result)
      end

      it "includes tool_name from tool_result" do
        result = tool.execute(arguments: { message_id: 3 }, history: history, context: context)

        expect(result["tool_name"]).to eq("file_read")
      end

      it "includes tool_output from tool_result" do
        result = tool.execute(arguments: { message_id: 3 }, history: history, context: context)

        expect(result["tool_output"]).to eq("File contents here")
      end
    end

    context "when message has error" do
      let(:message_with_error) do
        {
          "id" => 4,
          "role" => "assistant",
          "created_at" => "2024-01-01 12:00:00",
          "error" => "Something went wrong"
        }
      end

      before do
        allow(history).to receive(:get_message_by_id).and_return(message_with_error)
      end

      it "includes error_details" do
        result = tool.execute(arguments: { message_id: 4 }, history: history, context: context)

        expect(result["error_details"]).to eq("Something went wrong")
      end
    end

    context "when message has all optional fields" do
      let(:complete_message) do
        {
          "id" => 5,
          "role" => "assistant",
          "created_at" => "2024-01-01 13:00:00",
          "content" => "Message content",
          "tool_calls" => [{ "name" => "test_tool", "arguments" => {} }],
          "tool_result" => { "name" => "result_tool", "result" => "output" },
          "error" => "Error occurred"
        }
      end

      before do
        allow(history).to receive(:get_message_by_id).and_return(complete_message)
      end

      it "includes all optional fields" do
        result = tool.execute(arguments: { message_id: 5 }, history: history, context: context)

        expect(result["message_content"]).to eq("Message content")
        expect(result["tool_calls"]).to be_an(Array)
        expect(result["tool_name"]).to eq("result_tool")
        expect(result["tool_output"]).to eq("output")
        expect(result["error_details"]).to eq("Error occurred")
      end
    end

    context "when message is not found" do
      before do
        allow(history).to receive(:get_message_by_id).and_return(nil)
      end

      it "returns error message" do
        result = tool.execute(arguments: { message_id: 999 }, history: history, context: context)

        expect(result[:error]).to eq("Message not found or not accessible")
      end

      it "includes message_id in error response" do
        result = tool.execute(arguments: { message_id: 999 }, history: history, context: context)

        expect(result[:message_id]).to eq(999)
      end
    end

    context "when StandardError occurs" do
      before do
        allow(history).to receive(:get_message_by_id).and_raise(StandardError.new("Database error"))
      end

      it "returns error message" do
        result = tool.execute(arguments: { message_id: 1 }, history: history, context: context)

        expect(result[:error]).to eq("Failed to retrieve message: Database error")
      end

      it "includes message_id in error response" do
        result = tool.execute(arguments: { message_id: 1 }, history: history, context: context)

        expect(result[:message_id]).to eq(1)
      end
    end

    context "when context has application key" do
      it "accesses application from context without error" do
        allow(history).to receive(:get_message_by_id).and_return(
          { "id" => 1, "role" => "user", "created_at" => "2024-01-01" }
        )

        expect do
          tool.execute(arguments: { message_id: 1 }, history: history, context: context)
        end.not_to raise_error
      end
    end
  end
end
