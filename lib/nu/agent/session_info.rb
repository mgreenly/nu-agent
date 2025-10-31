# frozen_string_literal: true

module Nu
  module Agent
    # Builds session information text
    class SessionInfo
      def self.build(application)
        lines = []
        lines.concat(build_header_lines)
        lines.concat(build_models_lines(application))
        lines.concat(build_settings_lines(application))
        lines.concat(build_summarizer_status_lines(application))
        lines.concat(build_footer_lines(application))

        lines.join("\n")
      end

      def self.build_header_lines
        [
          "",
          "Version:       #{Nu::Agent::VERSION}",
          ""
        ]
      end

      def self.build_models_lines(application)
        [
          "Models:",
          "  Orchestrator:  #{application.orchestrator.model}",
          "  Spellchecker:  #{application.spellchecker.model}",
          "  Summarizer:    #{application.summarizer.model}",
          ""
        ]
      end

      def self.build_settings_lines(application)
        [
          "Debug mode:    #{application.debug}",
          "Redaction:     #{application.redact ? 'on' : 'off'}",
          "Summarizer:    #{application.summarizer_enabled ? 'on' : 'off'}"
        ]
      end

      def self.build_summarizer_status_lines(application)
        return [] unless application.summarizer_enabled

        status_lines = []
        application.status_mutex.synchronize do
          status = application.summarizer_status
          status_lines.concat(format_summarizer_status(status))
        end
        status_lines
      end

      def self.format_summarizer_status(status)
        if status["running"]
          format_running_status(status)
        elsif status["total"].positive?
          format_completed_status(status)
        else
          ["  Status:      idle"]
        end
      end

      def self.format_running_status(status)
        lines = ["  Status:      running (#{status['completed']}/#{status['total']} conversations)"]
        lines << "  Spend:       $#{format('%.6f', status['spend'])}" if status["spend"].positive?
        lines
      end

      def self.format_completed_status(status)
        completed = status["completed"]
        total = status["total"]
        failed = status["failed"]
        lines = ["  Status:      completed (#{completed}/#{total} conversations, #{failed} failed)"]
        lines << "  Spend:       $#{format('%.6f', status['spend'])}" if status["spend"].positive?
        lines
      end

      def self.build_footer_lines(application)
        [
          "Spellcheck:    #{application.spell_check_enabled ? 'on' : 'off'}",
          "Database:      #{File.expand_path(application.history.db_path)}"
        ]
      end
    end
  end
end
