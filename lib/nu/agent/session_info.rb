# frozen_string_literal: true

module Nu
  module Agent
    # Builds session information text
    class SessionInfo
      def self.build(application)
        lines = []
        lines << ""
        lines << "Version:       #{Nu::Agent::VERSION}"
        lines << ""

        # Models section
        lines << "Models:"
        lines << "  Orchestrator:  #{application.orchestrator.model}"
        lines << "  Spellchecker:  #{application.spellchecker.model}"
        lines << "  Summarizer:    #{application.summarizer.model}"
        lines << ""

        lines << "Debug mode:    #{application.debug}"
        lines << "Verbosity:     #{application.verbosity}"
        lines << "Redaction:     #{application.redact ? 'on' : 'off'}"
        lines << "Summarizer:    #{application.summarizer_enabled ? 'on' : 'off'}"

        # Show summarizer status if enabled
        if application.summarizer_enabled
          application.status_mutex.synchronize do
            status = application.summarizer_status
            if status["running"]
              lines << "  Status:      running (#{status['completed']}/#{status['total']} conversations)"
              lines << "  Spend:       $#{format('%.6f', status['spend'])}" if status["spend"].positive?
            elsif status["total"].positive?
              completed = status["completed"]
              total = status["total"]
              failed = status["failed"]
              lines << "  Status:      completed (#{completed}/#{total} conversations, #{failed} failed)"
              lines << "  Spend:       $#{format('%.6f', status['spend'])}" if status["spend"].positive?
            else
              lines << "  Status:      idle"
            end
          end
        end

        lines << "Spellcheck:    #{application.spell_check_enabled ? 'on' : 'off'}"
        lines << "Database:      #{File.expand_path(application.history.db_path)}"

        lines.join("\n")
      end
    end
  end
end
