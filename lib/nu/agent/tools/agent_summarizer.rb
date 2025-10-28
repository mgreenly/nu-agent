# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class AgentSummarizer
        PARAMETERS = {}.freeze

        def name
          "agent_summarizer"
        end

        def description
          "PREFERRED tool for checking background summarization status. " \
            "Returns progress information including how many conversations have been summarized, " \
            "how many failed, and what is currently being processed."
        end

        def parameters
          PARAMETERS
        end

        def execute(context:, **)
          application = context["application"]
          return error_response if application.nil?

          status = read_status(application)
          format_status_response(status)
        end

        private

        def error_response
          { "error" => "Application context not available" }
        end

        def read_status(application)
          application.status_mutex.synchronize do
            application.summarizer_status.dup
          end
        end

        def format_status_response(status)
          if status["running"]
            format_running_response(status)
          elsif status["total"].positive?
            format_completed_response(status)
          else
            format_idle_response
          end
        end

        def format_running_response(status)
          {
            "status" => "running",
            "progress" => "#{status['completed']}/#{status['total']} conversations",
            "total" => status["total"],
            "completed" => status["completed"],
            "failed" => status["failed"],
            "current_conversation_id" => status["current_conversation_id"],
            "last_summary" => status["last_summary"] ? truncate_summary(status["last_summary"]) : nil,
            "spend" => status["spend"]
          }
        end

        def format_completed_response(status)
          {
            "status" => "completed",
            "total" => status["total"],
            "completed" => status["completed"],
            "failed" => status["failed"],
            "last_summary" => status["last_summary"] ? truncate_summary(status["last_summary"]) : nil,
            "spend" => status["spend"]
          }
        end

        def format_idle_response
          {
            "status" => "idle",
            "message" => "No conversations to summarize",
            "spend" => 0.0
          }
        end

        def truncate_summary(summary)
          summary.length > 150 ? "#{summary[0..150]}..." : summary
        end
      end
    end
  end
end
