# frozen_string_literal: true

module Nu
  module Agent
    # Helper module for subsystem-specific debug output
    # Provides centralized verbosity checking and formatted debug output
    module SubsystemDebugger
      # Check if debug output should be shown for a subsystem
      # @param application [Application] The application instance
      # @param subsystem [String] The subsystem name (e.g., "llm", "tools")
      # @param level [Integer] The minimum verbosity level required
      # @return [Boolean] True if debug output should be shown
      def self.should_output?(application, subsystem, level)
        return false unless application&.debug

        # Don't access database from non-main threads (DuckDB thread-safety)
        # Workers have their own config_store, formatters should not access DB from threads
        return false unless Thread.current == Thread.main

        config_key = "#{subsystem}_verbosity"
        verbosity = application.history.get_int(config_key, default: 0)
        verbosity >= level
      end

      # Output debug message if verbosity level is sufficient
      # @param application [Application] The application instance
      # @param subsystem [String] The subsystem name
      # @param message [String] The debug message
      # @param level [Integer] The minimum verbosity level required
      def self.debug_output(application, subsystem, message, level:)
        return unless should_output?(application, subsystem, level)

        prefix = "[#{subsystem.capitalize}]"
        application.output_line("#{prefix} #{message}", type: :debug)
      end
    end
  end
end
