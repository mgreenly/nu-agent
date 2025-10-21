# frozen_string_literal: true

RSpec.describe Nu::Agent do
  it "has a version number" do
    expect(Nu::Agent::VERSION).not_to be nil
  end
end
