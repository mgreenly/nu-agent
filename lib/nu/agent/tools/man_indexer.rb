# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class ManIndexer
        PARAMETERS = {}.freeze

        def name
          "man_indexer"
        end

        def description
          "Check the status of background man page indexing. " \
            "Returns progress information including how many man pages have been indexed, " \
            "how many failed or were skipped, current batch being processed, and costs."
        end

        def parameters
          PARAMETERS
        end

        def execute(context:, **)
          application = context["application"]
          return error_response if application.nil?

          history = context["history"]
          enabled = history.get_config("index_man_enabled") == "true"
          status = read_status(application)

          format_response(enabled, status)
        end

        private

        def error_response
          { "error" => "Application context not available" }
        end

        def read_status(application)
          application.status_mutex.synchronize do
            application.man_indexer_status.dup
          end
        end

        def format_response(enabled, status)
          result = { "enabled" => enabled }

          if status["running"]
            result.merge(format_running_status(status))
          elsif status["total"].positive?
            result.merge(format_completed_status(status))
          else
            result.merge(format_idle_status)
          end
        end

        def format_running_status(status)
          {
            "running" => true,
            "progress" => build_progress_hash(status),
            "session" => build_session_hash(status),
            "current_batch" => status["current_batch"]
          }
        end

        def format_completed_status(status)
          {
            "running" => false,
            "progress" => build_progress_hash(status),
            "session" => build_session_hash(status)
          }
        end

        def format_idle_status
          {
            "running" => false,
            "message" => "Man page indexing not yet started"
          }
        end

        def build_progress_hash(status)
          {
            "total" => status["total"],
            "completed" => status["completed"],
            "failed" => status["failed"],
            "skipped" => status["skipped"],
            "remaining" => status["total"] - status["completed"]
          }
        end

        def build_session_hash(status)
          {
            "spend" => status["session_spend"],
            "tokens" => status["session_tokens"]
          }
        end
      end
    end
  end
end
