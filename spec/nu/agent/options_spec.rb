# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::Options do
  let(:captured_output) { StringIO.new }

  before do
    allow($stdout).to receive(:write) { |text| captured_output.write(text) }
    allow($stdout).to receive(:puts) { |text| captured_output.puts(text) }
    allow($stdout).to receive(:print) { |text| captured_output.print(text) }
  end

  describe "#initialize" do
    it "initializes with default values when no args provided" do
      options = described_class.new([])
      expect(options.reset_model).to be_nil
      expect(options.debug).to be false
      expect(options.banner_mode).to eq(:full)
    end

    it "uses ARGV by default if no args provided" do
      stub_const("ARGV", [])
      options = described_class.new
      expect(options.reset_model).to be_nil
      expect(options.debug).to be false
      expect(options.banner_mode).to eq(:full)
    end
  end

  describe "--reset-models flag" do
    it "sets reset_model when provided" do
      options = described_class.new(["--reset-models", "claude-3-5-sonnet-20241022"])
      expect(options.reset_model).to eq("claude-3-5-sonnet-20241022")
    end

    it "accepts any model name" do
      options = described_class.new(["--reset-models", "gpt-4"])
      expect(options.reset_model).to eq("gpt-4")
    end
  end

  describe "--debug flag" do
    it "sets debug to true when provided" do
      options = described_class.new(["--debug"])
      expect(options.debug).to be true
    end

    it "keeps debug false when not provided" do
      options = described_class.new([])
      expect(options.debug).to be false
    end
  end

  describe "banner options" do
    describe "--no-banner flag" do
      it "sets banner_mode to :none when provided" do
        options = described_class.new(["--no-banner"])
        expect(options.banner_mode).to eq(:none)
      end
    end

    describe "--minimal flag" do
      it "sets banner_mode to :minimal when provided" do
        options = described_class.new(["--minimal"])
        expect(options.banner_mode).to eq(:minimal)
      end
    end

    describe "default behavior" do
      it "sets banner_mode to :full when neither flag is provided" do
        options = described_class.new([])
        expect(options.banner_mode).to eq(:full)
      end
    end

    describe "conflicting options" do
      it "uses last option when both flags are provided (minimal wins)" do
        options = described_class.new(["--no-banner", "--minimal"])
        expect(options.banner_mode).to eq(:minimal)
      end

      it "uses last option when both flags are provided (no-banner wins)" do
        options = described_class.new(["--minimal", "--no-banner"])
        expect(options.banner_mode).to eq(:none)
      end
    end
  end

  describe "--version flag" do
    it "prints version and exits" do
      expect do
        described_class.new(["--version"])
      end.to raise_error(SystemExit)

      expect(captured_output.string).to include("nu-agent version")
      expect(captured_output.string).to include(Nu::Agent::VERSION)
    end

    it "exits with -v short form" do
      expect do
        described_class.new(["-v"])
      end.to raise_error(SystemExit)

      expect(captured_output.string).to include("nu-agent version")
    end
  end

  describe "--help flag" do
    before do
      # Mock ClientFactory.display_models - include default models
      allow(Nu::Agent::ClientFactory).to receive(:display_models).and_return(
        anthropic: ["claude-haiku-4-5", "claude-3-5-sonnet-20241022", "claude-3-opus-20240229"],
        google: ["gemini-2.5-flash-lite", "gemini-2.0-flash-exp", "gemini-1.5-pro"],
        openai: ["gpt-5-mini", "gpt-4o", "gpt-4-turbo"],
        xai: %w[grok-code-fast-1 grok-beta]
      )
    end

    it "prints help and exits" do
      expect do
        described_class.new(["--help"])
      end.to raise_error(SystemExit)

      output = captured_output.string
      expect(output).to include("Usage: nu-agent [options]")
      expect(output).to include("Available Models")
    end

    it "exits with -h short form" do
      expect do
        described_class.new(["-h"])
      end.to raise_error(SystemExit)

      expect(captured_output.string).to include("Usage: nu-agent [options]")
    end

    it "displays available models from all providers" do
      expect do
        described_class.new(["--help"])
      end.to raise_error(SystemExit)

      output = captured_output.string
      expect(output).to include("Anthropic:")
      expect(output).to include("Google:")
      expect(output).to include("OpenAI:")
      expect(output).to include("X.AI:")
    end

    it "marks default models with asterisk" do
      expect do
        described_class.new(["--help"])
      end.to raise_error(SystemExit)

      output = captured_output.string
      # Check that some model is marked as default
      expect(output).to match(/\w+\*/)
    end
  end

  describe "multiple flags" do
    it "handles both --reset-models and --debug" do
      options = described_class.new(["--reset-models", "gpt-4", "--debug"])
      expect(options.reset_model).to eq("gpt-4")
      expect(options.debug).to be true
    end
  end

  describe "#print_available_models" do
    before do
      # Mock ClientFactory.display_models - include default models
      allow(Nu::Agent::ClientFactory).to receive(:display_models).and_return(
        anthropic: ["claude-haiku-4-5", "claude-3-5-sonnet-20241022", "claude-3-opus-20240229"],
        google: ["gemini-2.5-flash-lite", "gemini-2.0-flash-exp", "gemini-1.5-pro"],
        openai: ["gpt-5-mini", "gpt-4o", "gpt-4-turbo"],
        xai: %w[grok-code-fast-1 grok-beta]
      )
    end

    it "prints models from ClientFactory" do
      options = described_class.new([])
      options.send(:print_available_models)

      output = captured_output.string
      expect(output).to include("claude-haiku-4-5")
      expect(output).to include("gemini-2.5-flash-lite")
      expect(output).to include("gpt-5-mini")
      expect(output).to include("grok-code-fast-1")
    end

    it "displays provider labels" do
      options = described_class.new([])
      options.send(:print_available_models)

      output = captured_output.string
      expect(output).to include("Anthropic:")
      expect(output).to include("Google:")
      expect(output).to include("OpenAI:")
      expect(output).to include("X.AI:")
    end

    it "marks default models correctly" do
      options = described_class.new([])
      options.send(:print_available_models)

      output = captured_output.string
      # Check that default models are marked with *
      expect(output).to include("#{Nu::Agent::Clients::Anthropic::DEFAULT_MODEL}*")
      expect(output).to include("#{Nu::Agent::Clients::Google::DEFAULT_MODEL}*")
      expect(output).to include("#{Nu::Agent::Clients::OpenAI::DEFAULT_MODEL}*")
      expect(output).to include("#{Nu::Agent::Clients::XAI::DEFAULT_MODEL}*")
    end
  end

  describe "#format_model_list" do
    it "marks the default model with asterisk" do
      options = described_class.new([])
      result = options.send(:format_model_list, %w[model-a model-b model-c], "model-b")
      expect(result).to eq("model-a, model-b*, model-c")
    end

    it "does not mark non-default models" do
      options = described_class.new([])
      result = options.send(:format_model_list, %w[model-a model-b], "model-c")
      expect(result).to eq("model-a, model-b")
    end

    it "handles single model list" do
      options = described_class.new([])
      result = options.send(:format_model_list, ["model-a"], "model-a")
      expect(result).to eq("model-a*")
    end

    it "handles empty list" do
      options = described_class.new([])
      result = options.send(:format_model_list, [], "default")
      expect(result).to eq("")
    end

    it "handles list where default is first" do
      options = described_class.new([])
      result = options.send(:format_model_list, %w[default model-b model-c], "default")
      expect(result).to eq("default*, model-b, model-c")
    end

    it "handles list where default is last" do
      options = described_class.new([])
      result = options.send(:format_model_list, %w[model-a model-b default], "default")
      expect(result).to eq("model-a, model-b, default*")
    end
  end
end
