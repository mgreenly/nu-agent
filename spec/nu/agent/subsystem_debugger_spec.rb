# frozen_string_literal: true

require "spec_helper"
require "nu/agent/subsystem_debugger"

RSpec.describe Nu::Agent::SubsystemDebugger do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:history) { instance_double("Nu::Agent::History") }

  before do
    allow(application).to receive(:history).and_return(history)
    allow(application).to receive(:output_line)
  end

  describe ".should_output?" do
    context "when debug is disabled" do
      it "returns false regardless of verbosity level" do
        allow(application).to receive(:debug).and_return(false)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(5)

        expect(described_class.should_output?(application, "llm", 2)).to be false
      end
    end

    context "when debug is enabled" do
      before do
        allow(application).to receive(:debug).and_return(true)
      end

      it "returns true when verbosity level is sufficient" do
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(3)

        expect(described_class.should_output?(application, "llm", 2)).to be true
        expect(described_class.should_output?(application, "llm", 3)).to be true
      end

      it "returns false when verbosity level is insufficient" do
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(1)

        expect(described_class.should_output?(application, "llm", 2)).to be false
      end

      it "defaults to 0 when verbosity not configured" do
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(0)

        expect(described_class.should_output?(application, "tools", 0)).to be true
        expect(described_class.should_output?(application, "tools", 1)).to be false
      end

      it "uses subsystem-specific config key" do
        allow(history).to receive(:get_int).with("stats_verbosity", default: 0).and_return(2)

        expect(described_class.should_output?(application, "stats", 1)).to be true
        expect(described_class.should_output?(application, "stats", 3)).to be false
      end
    end
  end

  describe ".debug_output" do
    context "when debug output should not be shown" do
      it "does not output anything" do
        allow(application).to receive(:debug).and_return(false)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(5)

        expect(application).not_to receive(:output_line)
        described_class.debug_output(application, "llm", "Test message", level: 2)
      end
    end

    context "when debug output should be shown" do
      before do
        allow(application).to receive(:debug).and_return(true)
        allow(history).to receive(:get_int).with("llm_verbosity", default: 0).and_return(3)
      end

      it "outputs message with subsystem prefix" do
        expect(application).to receive(:output_line).with("[Llm] Test message", type: :debug)
        described_class.debug_output(application, "llm", "Test message", level: 2)
      end

      it "capitalizes subsystem name in prefix" do
        allow(history).to receive(:get_int).with("tools_verbosity", default: 0).and_return(2)
        expect(application).to receive(:output_line).with("[Tools] Tool called", type: :debug)
        described_class.debug_output(application, "tools", "Tool called", level: 1)
      end
    end
  end
end
