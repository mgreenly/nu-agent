# frozen_string_literal: true

require "json"

module Nu
  module Agent
    # Filters and redacts sensitive information from text before storage
    class RedactionFilter
      # Default patterns for common sensitive data
      DEFAULT_PATTERNS = [
        # API keys (OpenAI, Anthropic, etc.)
        { pattern: /\b(sk|pk)-[a-zA-Z0-9]{6,}/, replacement: "[REDACTED_API_KEY]" },
        # Email addresses
        { pattern: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, replacement: "[REDACTED_EMAIL]" },
        # Secret keys and passwords in common formats
        { pattern: /(?:SECRET|PASSWORD|PASS|PWD|KEY)[_\s]*[=:]\s*['"]?[^\s'"]{8,}['"]?/i,
          replacement: "[REDACTED_SECRET]" },
        # Bearer tokens
        { pattern: /Bearer\s+[A-Za-z0-9\-._~+\/]+=*/i, replacement: "Bearer [REDACTED_TOKEN]" },
        # JWT tokens
        { pattern: /eyJ[A-Za-z0-9\-._~+\/]+=*\.eyJ[A-Za-z0-9\-._~+\/]+=*\.[A-Za-z0-9\-._~+\/]+=*/,
          replacement: "[REDACTED_TOKEN]" }
      ].freeze

      def initialize(config_store)
        @config_store = config_store
      end

      # Check if redaction is enabled
      def enabled?
        @config_store.get_bool("redaction_enabled", default: false)
      end

      # Redact sensitive information from text
      def redact(text)
        return text unless enabled?
        return text if text.nil? || text.empty?

        redacted = text.dup
        patterns = load_patterns

        patterns.each do |pattern_config|
          pattern = pattern_config[:pattern]
          replacement = pattern_config[:replacement]
          redacted = redacted.gsub(pattern, replacement)
        end

        redacted
      end

      private

      def load_patterns
        patterns = DEFAULT_PATTERNS.dup

        # Load custom patterns from config if available
        custom_patterns_json = @config_store.get_config("redaction_patterns", default: nil)
        return patterns if custom_patterns_json.nil? || custom_patterns_json.strip.empty?

        begin
          custom_patterns = JSON.parse(custom_patterns_json)
          custom_patterns.each do |pattern_def|
            patterns << {
              pattern: Regexp.new(pattern_def["pattern"]),
              replacement: pattern_def["replacement"]
            }
          end
        rescue JSON::ParserError, RegexpError => e
          # If custom patterns are malformed, just use defaults
          # Silent failure to avoid cluttering output in tests
        end

        patterns
      end
    end
  end
end
