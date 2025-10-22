# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class GetSummarizerStatus
        def name
          "get_summarizer_status"
        end

        def description
          "Get the current status of the background conversation summarization worker. Returns progress information including how many conversations have been summarized, how many failed, and what it's currently working on."
        end

        def parameters
          {} # No parameters needed
        end

        def execute(arguments:, history:, context:)
          # Get the Application instance from context
          # The context includes the Application's summarizer_status and status_mutex
          application = context['application']

          if application.nil?
            return {
              'error' => 'Application context not available'
            }
          end

          # Read status under mutex
          status = nil
          application.status_mutex.synchronize do
            status = application.summarizer_status.dup
          end

          # Format the response
          if status['running']
            {
              'status' => 'running',
              'progress' => "#{status['completed']}/#{status['total']} conversations",
              'total' => status['total'],
              'completed' => status['completed'],
              'failed' => status['failed'],
              'current_conversation_id' => status['current_conversation_id'],
              'last_summary' => status['last_summary'] ? truncate_summary(status['last_summary']) : nil,
              'spend' => status['spend']
            }
          else
            if status['total'] > 0
              # Finished
              {
                'status' => 'completed',
                'total' => status['total'],
                'completed' => status['completed'],
                'failed' => status['failed'],
                'last_summary' => status['last_summary'] ? truncate_summary(status['last_summary']) : nil,
                'spend' => status['spend']
              }
            else
              # Not started or no conversations to summarize
              {
                'status' => 'idle',
                'message' => 'No conversations to summarize',
                'spend' => 0.0
              }
            end
          end
        end

        private

        def truncate_summary(summary)
          summary.length > 150 ? "#{summary[0..150]}..." : summary
        end
      end
    end
  end
end
