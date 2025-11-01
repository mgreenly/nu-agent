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

  describe "#with_rag_content" do
    it "stores the RAG content and returns self for chaining" do
      builder = described_class.new
      rag_content = {
        redactions: %w[secret1 secret2],
        spell_check: { typos: [] }
      }

      result = builder.with_rag_content(rag_content)

      expect(result).to be(builder)
      expect(builder.rag_content).to eq(rag_content)
    end
  end

  describe "#with_user_query" do
    it "stores the user query and returns self for chaining" do
      builder = described_class.new
      query = "What is the weather today?"

      result = builder.with_user_query(query)

      expect(result).to be(builder)
      expect(builder.user_query).to eq(query)
    end
  end

  describe "#with_tools" do
    it "stores the tools and returns self for chaining" do
      builder = described_class.new
      tools = [
        { name: "get_weather", schema: { type: "object" } },
        { name: "search", schema: { type: "object" } }
      ]

      result = builder.with_tools(tools)

      expect(result).to be(builder)
      expect(builder.tools).to eq(tools)
    end
  end

  describe "#with_metadata" do
    it "stores the metadata and returns self for chaining" do
      builder = described_class.new
      metadata = {
        conversation_id: 123,
        exchange_id: 456,
        request_type: "tool_call"
      }

      result = builder.with_metadata(metadata)

      expect(result).to be(builder)
      expect(builder.metadata).to eq(metadata)
    end
  end

  describe "#build" do
    context "when all required fields are provided" do
      it "returns a properly structured internal format hash" do
        builder = described_class.new
                                 .with_system_prompt("You are a helpful assistant")
                                 .with_user_query("What is 2+2?")

        result = builder.build

        expect(result).to be_a(Hash)
        expect(result[:system_prompt]).to eq("You are a helpful assistant")
        expect(result[:messages]).to be_a(Array)
        expect(result[:messages].last).to eq({ role: "user", content: "What is 2+2?" })
      end

      it "includes all optional fields when provided" do
        builder = described_class.new
                                 .with_system_prompt("You are a helpful assistant")
                                 .with_history([{ role: "user", content: "Hello" }])
                                 .with_rag_content({ redactions: ["secret"] })
                                 .with_user_query("What is 2+2?")
                                 .with_tools([{ name: "calculator" }])
                                 .with_metadata({ conversation_id: 123 })

        result = builder.build

        expect(result[:system_prompt]).to eq("You are a helpful assistant")
        expect(result[:messages]).to be_a(Array)
        expect(result[:tools]).to eq([{ name: "calculator" }])
        expect(result[:metadata]).to be_a(Hash)
        expect(result[:metadata][:rag_content]).to eq({ redactions: ["secret"] })
        expect(result[:metadata][:user_query]).to eq("What is 2+2?")
        expect(result[:metadata][:conversation_id]).to eq(123)
      end

      it "constructs messages from history and user_query" do
        builder = described_class.new
                                 .with_system_prompt("You are a helpful assistant")
                                 .with_history([
                                                 { role: "user", content: "Hello" },
                                                 { role: "assistant", content: "Hi there!" }
                                               ])
                                 .with_user_query("How are you?")

        result = builder.build

        expect(result[:messages]).to eq([
                                          { role: "user", content: "Hello" },
                                          { role: "assistant", content: "Hi there!" },
                                          { role: "user", content: "How are you?" }
                                        ])
      end

      it "handles user_query without history" do
        builder = described_class.new
                                 .with_system_prompt("You are a helpful assistant")
                                 .with_user_query("What is 2+2?")

        result = builder.build

        expect(result[:messages]).to eq([
                                          { role: "user", content: "What is 2+2?" }
                                        ])
      end

      it "handles history without user_query" do
        builder = described_class.new
                                 .with_system_prompt("You are a helpful assistant")
                                 .with_history([
                                                 { role: "user", content: "Hello" },
                                                 { role: "assistant", content: "Hi there!" }
                                               ])

        result = builder.build

        expect(result[:messages]).to eq([
                                          { role: "user", content: "Hello" },
                                          { role: "assistant", content: "Hi there!" }
                                        ])
      end
    end

    context "when required fields are missing" do
      it "raises an error when system_prompt is missing" do
        builder = described_class.new.with_user_query("What is 2+2?")

        expect { builder.build }.to raise_error(ArgumentError, /system_prompt is required/)
      end

      it "raises an error when both user_query and history are missing" do
        builder = described_class.new.with_system_prompt("You are a helpful assistant")

        expect { builder.build }.to raise_error(ArgumentError, /messages are required/)
      end
    end

    context "when building metadata" do
      it "omits metadata entirely when no metadata components are present" do
        builder = described_class.new
                                 .with_system_prompt("You are a helpful assistant")
                                 .with_user_query("What is 2+2?")

        result = builder.build

        expect(result.key?(:metadata)).to be false
      end

      it "includes only metadata fields that were set" do
        builder = described_class.new
                                 .with_system_prompt("You are a helpful assistant")
                                 .with_user_query("What is 2+2?")
                                 .with_metadata({ conversation_id: 123 })

        result = builder.build

        expect(result[:metadata]).to eq({
                                          user_query: "What is 2+2?",
                                          conversation_id: 123
                                        })
      end
    end
  end
end
