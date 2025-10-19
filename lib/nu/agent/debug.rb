# frozen_string_literal: true

module Nu
  module Agent
    # Centralized debug logging for the entire application
    class Debug
      class << self
        attr_writer :enabled

        def enabled?
          @enabled ||= false
        end

        # Log a single line message
        def log(message)
          puts "[DEBUG] #{message}" if enabled?
        end

        # Log multi-line content with [DEBUG] prefix on every line
        def log_multiline(header, content)
          return unless enabled?

          puts "[DEBUG] #{header}"
          content.each_line do |line|
            puts "[DEBUG] #{line.chomp}"
          end
        end
      end
    end
  end
end
