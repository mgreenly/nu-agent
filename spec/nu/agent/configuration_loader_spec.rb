# frozen_string_literal: true

require "spec_helper"
require "nu/agent/configuration_loader"

RSpec.describe Nu::Agent::ConfigurationLoader do
  let(:history) { double("history") }
  let(:options) { double("options", reset_model: nil, debug: false) }
  let(:orchestrator) { double("orchestrator", model: "claude-sonnet-4-5") }
  let(:spellchecker) { double("spellchecker", model: "claude-haiku-4-5") }
  let(:summarizer) { double("summarizer", model: "claude-haiku-4-5") }

  before do
    # Mock history.get_config calls for model configurations
    allow(history).to receive(:get_config).with("model_orchestrator").and_return("claude-sonnet-4-5")
    allow(history).to receive(:get_config).with("model_spellchecker").and_return("claude-haiku-4-5")
    allow(history).to receive(:get_config).with("model_summarizer").and_return("claude-haiku-4-5")

    # Mock history.get_config calls for settings
    allow(history).to receive(:get_config).with("debug", default: "false").and_return("false")
    allow(history).to receive(:get_config).with("verbosity", default: "0").and_return("0")
    allow(history).to receive(:get_config).with("redaction", default: "true").and_return("true")
    allow(history).to receive(:get_config).with("summarizer_enabled", default: "true").and_return("true")
    allow(history).to receive(:get_config).with("spell_check_enabled", default: "true").and_return("true")

    # Mock ClientFactory - return different instances for each call
    allow(Nu::Agent::ClientFactory).to receive(:create)
      .with("claude-sonnet-4-5").and_return(orchestrator)
    allow(Nu::Agent::ClientFactory).to receive(:create)
      .with("claude-haiku-4-5").and_return(spellchecker, summarizer)
  end

  describe ".load" do
    it "returns a configuration object with all loaded values" do
      config = described_class.load(history: history, options: options)

      expect(config).to be_a(Nu::Agent::ConfigurationLoader::Configuration)
      expect(config.orchestrator).to eq(orchestrator)
      expect(config.spellchecker).to eq(spellchecker)
      expect(config.summarizer).to eq(summarizer)
      expect(config.debug).to be(false)
      expect(config.verbosity).to eq(0)
      expect(config.redact).to be(true)
      expect(config.summarizer_enabled).to be(true)
      expect(config.spell_check_enabled).to be(true)
    end

    context "when reset_model option is provided" do
      let(:options) { double("options", reset_model: "gpt-5", debug: false) }
      let(:gpt_client) { double("gpt_client", model: "gpt-5") }

      before do
        allow(history).to receive(:set_config)
        allow(Nu::Agent::ClientFactory).to receive(:create).with("gpt-5").and_return(gpt_client)
      end

      it "resets all model configurations to the specified model" do
        config = described_class.load(history: history, options: options)

        expect(history).to have_received(:set_config).with("model_orchestrator", "gpt-5")
        expect(history).to have_received(:set_config).with("model_spellchecker", "gpt-5")
        expect(history).to have_received(:set_config).with("model_summarizer", "gpt-5")
        expect(config.orchestrator).to eq(gpt_client)
        expect(config.spellchecker).to eq(gpt_client)
        expect(config.summarizer).to eq(gpt_client)
      end
    end

    context "when models are not configured and no reset_model option" do
      before do
        allow(history).to receive(:get_config).with("model_orchestrator").and_return(nil)
        allow(history).to receive(:get_config).with("model_spellchecker").and_return(nil)
        allow(history).to receive(:get_config).with("model_summarizer").and_return(nil)
      end

      it "raises an error" do
        expect do
          described_class.load(history: history, options: options)
        end.to raise_error(Nu::Agent::Error, /Models not configured/)
      end
    end

    context "when debug option is provided" do
      let(:options) { double("options", reset_model: nil, debug: true) }

      it "overrides database debug setting" do
        config = described_class.load(history: history, options: options)

        expect(config.debug).to be(true)
      end
    end

    context "when database has debug enabled" do
      before do
        allow(history).to receive(:get_config).with("debug", default: "false").and_return("true")
      end

      it "loads debug as true" do
        config = described_class.load(history: history, options: options)

        expect(config.debug).to be(true)
      end
    end

    context "when verbosity is set in database" do
      before do
        allow(history).to receive(:get_config).with("verbosity", default: "0").and_return("3")
      end

      it "loads verbosity as integer" do
        config = described_class.load(history: history, options: options)

        expect(config.verbosity).to eq(3)
      end
    end

    context "when redaction is disabled in database" do
      before do
        allow(history).to receive(:get_config).with("redaction", default: "true").and_return("false")
      end

      it "loads redact as false" do
        config = described_class.load(history: history, options: options)

        expect(config.redact).to be(false)
      end
    end
  end
end
