# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::RedactionFilter do
  let(:config_store) { instance_double(Nu::Agent::ConfigStore) }
  let(:filter) { described_class.new(config_store) }

  before do
    # Default: redaction disabled
    allow(config_store).to receive(:get_bool).with("redaction_enabled", default: false).and_return(false)
  end

  describe "#initialize" do
    it "initializes with config_store" do
      expect(filter).to be_a(described_class)
    end
  end

  describe "#redact" do
    context "when redaction is disabled" do
      it "returns original text unchanged" do
        text = "My API key is sk-1234567890abcdef and my email is test@example.com"
        expect(filter.redact(text)).to eq(text)
      end
    end

    context "when redaction is enabled" do
      before do
        allow(config_store).to receive(:get_bool).with("redaction_enabled", default: false).and_return(true)
        allow(config_store).to receive(:get_config).with("redaction_patterns", default: anything).and_return(nil)
      end

      it "redacts common API key patterns" do
        text = "My API key is sk-1234567890abcdef"
        redacted = filter.redact(text)
        expect(redacted).to include("[REDACTED_API_KEY]")
        expect(redacted).not_to include("sk-1234567890abcdef")
      end

      it "redacts email addresses" do
        text = "Contact me at user@example.com for details"
        redacted = filter.redact(text)
        expect(redacted).to include("[REDACTED_EMAIL]")
        expect(redacted).not_to include("user@example.com")
      end

      it "redacts common secret key patterns" do
        text = "SECRET_KEY=abc123def456ghi789"
        redacted = filter.redact(text)
        expect(redacted).to include("[REDACTED_SECRET]")
        expect(redacted).not_to include("abc123def456ghi789")
      end

      it "redacts bearer tokens" do
        text = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        redacted = filter.redact(text)
        expect(redacted).to include("[REDACTED_TOKEN]")
        expect(redacted).not_to include("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9")
      end

      it "redacts multiple patterns in the same text" do
        text = "Email: admin@test.com, Token: sk-abc123, Secret: KEY_def456"
        redacted = filter.redact(text)
        expect(redacted).to include("[REDACTED_EMAIL]")
        expect(redacted).to include("[REDACTED_API_KEY]")
        expect(redacted).to include("[REDACTED_SECRET]")
        expect(redacted).not_to include("admin@test.com")
        expect(redacted).not_to include("sk-abc123")
        expect(redacted).not_to include("def456")
      end

      it "handles empty strings" do
        expect(filter.redact("")).to eq("")
      end

      it "handles nil input" do
        expect(filter.redact(nil)).to be_nil
      end
    end

    context "with custom redaction patterns" do
      before do
        allow(config_store).to receive(:get_bool).with("redaction_enabled", default: false).and_return(true)
        # Custom pattern to redact credit card numbers
        # Note: In JSON, regex patterns need double-escaping:
        # \\\\b becomes \\b in parsed string, which is word boundary in regex
        custom_patterns = '[{"pattern": ' \
                          '"\\\\b\\\\d{4}[\\\\s-]?\\\\d{4}[\\\\s-]?\\\\d{4}[\\\\s-]?\\\\d{4}\\\\b", ' \
                          '"replacement": "[REDACTED_CC]"}]'
        allow(config_store).to receive(:get_config).with("redaction_patterns",
                                                         default: anything).and_return(custom_patterns)
      end

      it "applies custom patterns" do
        text = "Card number: 1234 5678 9012 3456"
        redacted = filter.redact(text)
        expect(redacted).to include("[REDACTED_CC]")
        expect(redacted).not_to include("1234 5678 9012 3456")
      end
    end
  end

  describe "#enabled?" do
    it "returns false when redaction is disabled" do
      expect(filter.enabled?).to be false
    end

    it "returns true when redaction is enabled" do
      allow(config_store).to receive(:get_bool).with("redaction_enabled", default: false).and_return(true)
      expect(filter.enabled?).to be true
    end
  end
end
