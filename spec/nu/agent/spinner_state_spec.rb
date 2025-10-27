# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::SpinnerState do
  subject(:state) { described_class.new }

  describe "#initialize" do
    it "starts with running false" do
      expect(state.running).to be false
    end

    it "starts with empty message" do
      expect(state.message).to eq("")
    end

    it "starts with frame 0" do
      expect(state.frame).to eq(0)
    end

    it "starts with nil parent_thread" do
      expect(state.parent_thread).to be_nil
    end

    it "starts with interrupt_requested false" do
      expect(state.interrupt_requested).to be false
    end
  end

  describe "#active?" do
    it "returns false initially" do
      expect(state.active?).to be false
    end

    it "returns false when running but no parent_thread" do
      state.running = true
      expect(state.active?).to be false
    end

    it "returns false when parent_thread exists but not running" do
      state.parent_thread = Thread.current
      expect(state.active?).to be false
    end

    it "returns true when both running and parent_thread exist" do
      state.running = true
      state.parent_thread = Thread.current
      expect(state.active?).to be true
    end
  end

  describe "#start" do
    let(:parent) { Thread.current }

    it "sets running to true" do
      state.start("Loading...", parent)
      expect(state.running).to be true
    end

    it "sets the message" do
      state.start("Processing...", parent)
      expect(state.message).to eq("Processing...")
    end

    it "resets frame to 0" do
      state.frame = 5
      state.start("Working...", parent)
      expect(state.frame).to eq(0)
    end

    it "sets the parent_thread" do
      state.start("Thinking...", parent)
      expect(state.parent_thread).to eq(parent)
    end

    it "resets interrupt_requested to false" do
      state.interrupt_requested = true
      state.start("Running...", parent)
      expect(state.interrupt_requested).to be false
    end
  end

  describe "#stop" do
    it "sets running to false" do
      state.running = true
      state.stop
      expect(state.running).to be false
    end
  end

  describe "#reset" do
    before do
      state.running = true
      state.message = "Test message"
      state.frame = 7
      state.parent_thread = Thread.current
      state.interrupt_requested = true
    end

    it "resets running to false" do
      state.reset
      expect(state.running).to be false
    end

    it "resets message to empty string" do
      state.reset
      expect(state.message).to eq("")
    end

    it "resets frame to 0" do
      state.reset
      expect(state.frame).to eq(0)
    end

    it "resets parent_thread to nil" do
      state.reset
      expect(state.parent_thread).to be_nil
    end

    it "resets interrupt_requested to false" do
      state.reset
      expect(state.interrupt_requested).to be false
    end
  end

  describe "attr_accessors" do
    it "allows setting and getting running" do
      state.running = true
      expect(state.running).to be true
    end

    it "allows setting and getting message" do
      state.message = "Custom message"
      expect(state.message).to eq("Custom message")
    end

    it "allows setting and getting frame" do
      state.frame = 3
      expect(state.frame).to eq(3)
    end

    it "allows setting and getting parent_thread" do
      thread = Thread.current
      state.parent_thread = thread
      expect(state.parent_thread).to eq(thread)
    end

    it "allows setting and getting interrupt_requested" do
      state.interrupt_requested = true
      expect(state.interrupt_requested).to be true
    end
  end
end
