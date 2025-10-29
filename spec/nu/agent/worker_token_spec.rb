# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::WorkerToken do
  subject(:token) { described_class.new(history) }

  let(:history) { instance_double(Nu::Agent::History) }

  describe "#initialize" do
    it "starts in inactive state" do
      expect(token.active?).to be false
    end
  end

  describe "#activate" do
    it "increments worker count" do
      expect(history).to receive(:increment_workers).once
      token.activate
    end

    it "sets active state to true" do
      allow(history).to receive(:increment_workers)
      token.activate
      expect(token.active?).to be true
    end

    it "is idempotent - only increments once on multiple calls" do
      expect(history).to receive(:increment_workers).once
      token.activate
      token.activate
      token.activate
    end
  end

  describe "#release" do
    context "when token is active" do
      before do
        allow(history).to receive(:increment_workers)
        token.activate
      end

      it "decrements worker count" do
        expect(history).to receive(:decrement_workers).once
        token.release
      end

      it "sets active state to false" do
        allow(history).to receive(:decrement_workers)
        token.release
        expect(token.active?).to be false
      end

      it "is idempotent - only decrements once on multiple calls" do
        expect(history).to receive(:decrement_workers).once
        token.release
        token.release
        token.release
      end
    end

    context "when token is inactive" do
      it "does not decrement worker count" do
        expect(history).not_to receive(:decrement_workers)
        token.release
      end
    end
  end

  describe "#active?" do
    it "returns false initially" do
      expect(token.active?).to be false
    end

    it "returns true after activation" do
      allow(history).to receive(:increment_workers)
      token.activate
      expect(token.active?).to be true
    end

    it "returns false after release" do
      allow(history).to receive(:increment_workers)
      allow(history).to receive(:decrement_workers)
      token.activate
      token.release
      expect(token.active?).to be false
    end
  end

  describe "thread safety" do
    it "handles concurrent activate calls safely" do
      allow(history).to receive(:increment_workers)
      threads = 10.times.map do
        Thread.new { token.activate }
      end
      threads.each(&:join)

      # Should only increment once despite 10 concurrent calls
      expect(token.active?).to be true
    end

    it "handles concurrent release calls safely" do
      allow(history).to receive(:increment_workers)
      allow(history).to receive(:decrement_workers)
      token.activate

      threads = 10.times.map do
        Thread.new { token.release }
      end
      threads.each(&:join)

      # Should only decrement once despite 10 concurrent calls
      expect(token.active?).to be false
    end
  end
end
