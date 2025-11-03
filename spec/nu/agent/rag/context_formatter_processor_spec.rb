# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::RAG::ContextFormatterProcessor do
  let(:config_store) { double("config_store") }
  let(:processor) { described_class.new(config_store: config_store) }
  let(:context) { Nu::Agent::RAG::RAGContext.new(query: "test query") }

  before do
    allow(config_store).to receive(:get_int).with("rag_token_budget", default: 2000).and_return(2000)
    allow(config_store).to receive(:get_float).with("rag_conversation_budget_pct", default: 0.4).and_return(0.4)
  end

  describe "#process" do
    context "with conversations and exchanges" do
      before do
        context.conversations = [
          { conversation_id: 1, content: "First conversation about Ruby", created_at: Time.now - 3600,
            similarity: 0.9 },
          { conversation_id: 2, content: "Second conversation about Rails", created_at: Time.now - 1800,
            similarity: 0.8 }
        ]
        context.exchanges = [
          { exchange_id: 5, content: "Exchange about testing", started_at: Time.now - 900, similarity: 0.85 },
          { exchange_id: 6, content: "Exchange about deployment", started_at: Time.now - 450, similarity: 0.75 }
        ]
      end

      it "formats both sections" do
        processor.process(context)

        expect(context.formatted_context).to include("## Related Conversations")
        expect(context.formatted_context).to include("## Related Exchanges")
        expect(context.formatted_context).to include("[Conversation #1]")
        expect(context.formatted_context).to include("[Exchange #5]")
      end

      it "sorts by similarity with recency as tie-breaker" do
        processor.process(context)

        # Higher similarity should come first
        conv1_pos = context.formatted_context.index("[Conversation #1]")
        conv2_pos = context.formatted_context.index("[Conversation #2]")
        expect(conv1_pos).to be < conv2_pos
      end

      it "updates metadata with token count" do
        processor.process(context)

        expect(context.metadata[:total_tokens]).to be > 0
      end
    end

    context "with empty results" do
      before do
        context.conversations = []
        context.exchanges = []
      end

      it "returns empty formatted context" do
        processor.process(context)

        expect(context.formatted_context).to eq("")
      end
    end

    context "with token budget constraints" do
      before do
        # Set very small budget
        allow(config_store).to receive(:get_int).with("rag_token_budget", default: 2000).and_return(50)

        # Add many conversations
        context.conversations = (1..10).map do |i|
          {
            conversation_id: i,
            content: "This is a long conversation about various topics " * 10,
            created_at: Time.now - (i * 3600),
            similarity: 0.9 - (i * 0.01)
          }
        end
      end

      it "respects token budget and truncates content" do
        processor.process(context)

        # Should not include all conversations due to budget
        conversation_count = context.formatted_context.scan("[Conversation #").length
        expect(conversation_count).to be < 10
        expect(context.metadata[:total_tokens]).to be <= 50
      end
    end

    context "when one section is empty" do
      before do
        context.conversations = [
          { conversation_id: 1, content: "Only conversation", created_at: Time.now, similarity: 0.9 }
        ]
        context.exchanges = []
      end

      it "only formats the non-empty section" do
        processor.process(context)

        expect(context.formatted_context).to include("## Related Conversations")
        expect(context.formatted_context).not_to include("## Related Exchanges")
      end
    end

    context "with nil timestamps" do
      before do
        context.conversations = [
          { conversation_id: 1, content: "Conversation with nil created_at", created_at: nil, similarity: 0.9 },
          { conversation_id: 2, content: "Conversation with timestamp", created_at: Time.now, similarity: 0.9 }
        ]
        context.exchanges = [
          { exchange_id: 1, content: "Exchange with nil started_at", started_at: nil, similarity: 0.8 },
          { exchange_id: 2, content: "Exchange with timestamp", started_at: Time.now, similarity: 0.8 }
        ]
      end

      it "handles nil timestamps gracefully" do
        processor.process(context)

        expect(context.formatted_context).to include("[Conversation #1]")
        expect(context.formatted_context).to include("[Conversation #2]")
        expect(context.formatted_context).to include("[Exchange #1]")
        expect(context.formatted_context).to include("[Exchange #2]")
      end
    end

    context "when exchange budget allows only header" do
      before do
        # Set budget where exchanges get very few tokens
        allow(config_store).to receive(:get_int).with("rag_token_budget", default: 2000).and_return(10)

        context.conversations = []
        context.exchanges = [
          { exchange_id: 1, content: "Very long exchange content that won't fit" * 10, started_at: Time.now,
            similarity: 0.9 }
        ]
      end

      it "returns empty string when only header would fit" do
        processor.process(context)

        expect(context.formatted_context).to eq("")
      end
    end

    context "when exchange breaks on budget limit" do
      before do
        # Set budget that allows some but not all exchanges
        allow(config_store).to receive(:get_int).with("rag_token_budget", default: 2000).and_return(100)

        context.conversations = []
        context.exchanges = [
          { exchange_id: 1, content: "Short", started_at: Time.now, similarity: 0.9 },
          { exchange_id: 2, content: "Very long exchange that will exceed budget " * 20, started_at: Time.now - 100,
            similarity: 0.8 }
        ]
      end

      it "includes entries until budget exceeded" do
        processor.process(context)

        expect(context.formatted_context).to include("[Exchange #1]")
        expect(context.formatted_context).not_to include("[Exchange #2]")
      end
    end
  end
end
