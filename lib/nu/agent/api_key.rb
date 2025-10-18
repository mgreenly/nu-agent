# frozen_string_literal: true

module Nu
  module Agent
    class ApiKey
      def initialize(key)
        @key = key
      end

      def to_s
        "REDACTED"
      end

      def inspect
        "#<Nu::Agent::ApiKey REDACTED>"
      end

      def present?
        !@key.nil? && !@key.empty?
      end

      def value
        @key
      end
    end
  end
end
