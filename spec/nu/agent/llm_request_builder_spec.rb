# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::LlmRequestBuilder do
  describe "#initialize" do
    it "creates a new builder instance" do
      builder = described_class.new
      expect(builder).to be_a(described_class)
    end
  end
end
