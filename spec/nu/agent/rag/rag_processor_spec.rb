# frozen_string_literal: true

require "spec_helper"
require "nu/agent/rag/rag_processor"

RSpec.describe Nu::Agent::RAG::RAGProcessor do
  # Create a concrete subclass for testing the abstract base class
  let(:test_processor_class) do
    Class.new(described_class) do
      attr_accessor :process_called

      def initialize
        super
        @process_called = false
      end

      protected

      def process_internal(context)
        @process_called = true
        context[:test_data] = "processed"
      end
    end
  end

  let(:processor) { test_processor_class.new }
  let(:context) { {} }

  describe "#initialize" do
    it "initializes with next_processor as nil" do
      expect(processor.next_processor).to be_nil
    end
  end

  describe "#next_processor=" do
    it "allows setting the next processor in the chain" do
      next_proc = test_processor_class.new
      processor.next_processor = next_proc
      expect(processor.next_processor).to eq(next_proc)
    end
  end

  describe "#process" do
    it "calls process_internal with the context" do
      processor.process(context)
      expect(processor.process_called).to be true
    end

    it "modifies the context during processing" do
      result = processor.process(context)
      expect(result[:test_data]).to eq("processed")
    end

    it "returns the context after processing" do
      result = processor.process(context)
      expect(result).to eq(context)
    end

    context "with a chain of processors" do
      let(:processor2) { test_processor_class.new }
      let(:processor3) { test_processor_class.new }

      before do
        processor.next_processor = processor2
        processor2.next_processor = processor3
      end

      it "processes through the entire chain" do
        processor.process(context)
        expect(processor.process_called).to be true
        expect(processor2.process_called).to be true
        expect(processor3.process_called).to be true
      end

      it "returns the final context after chain processing" do
        result = processor.process(context)
        expect(result).to eq(context)
        expect(result[:test_data]).to eq("processed")
      end
    end

    context "with no next processor" do
      it "processes successfully with nil next_processor" do
        expect { processor.process(context) }.not_to raise_error
        expect(processor.process_called).to be true
      end
    end
  end

  describe "#process_internal" do
    it "raises NotImplementedError when called on base class" do
      base_processor = described_class.new
      expect { base_processor.send(:process_internal, context) }.to raise_error(
        NotImplementedError,
        "Subclasses must implement process_internal"
      )
    end
  end
end
