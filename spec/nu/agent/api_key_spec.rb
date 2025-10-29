# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::ApiKey do
  describe "#initialize" do
    it "stores the provided key" do
      api_key = described_class.new("secret_key_123")

      expect(api_key.value).to eq("secret_key_123")
    end
  end

  describe "#to_s" do
    it "returns REDACTED instead of the actual key" do
      api_key = described_class.new("secret_key_123")

      expect(api_key.to_s).to eq("REDACTED")
    end
  end

  describe "#inspect" do
    it "returns a redacted inspection string" do
      api_key = described_class.new("secret_key_123")

      expect(api_key.inspect).to eq("#<Nu::Agent::ApiKey REDACTED>")
    end
  end

  describe "#present?" do
    context "when key is present" do
      it "returns true for a valid key" do
        api_key = described_class.new("valid_key")

        expect(api_key.present?).to be true
      end
    end

    context "when key is nil" do
      it "returns false" do
        api_key = described_class.new(nil)

        expect(api_key.present?).to be false
      end
    end

    context "when key is empty string" do
      it "returns false" do
        api_key = described_class.new("")

        expect(api_key.present?).to be false
      end
    end
  end

  describe "#value" do
    it "returns the actual key value" do
      api_key = described_class.new("actual_secret_key")

      expect(api_key.value).to eq("actual_secret_key")
    end

    it "returns nil if key was initialized with nil" do
      api_key = described_class.new(nil)

      expect(api_key.value).to be_nil
    end

    it "returns empty string if key was initialized with empty string" do
      api_key = described_class.new("")

      expect(api_key.value).to eq("")
    end
  end
end
