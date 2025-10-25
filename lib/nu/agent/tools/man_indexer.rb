# frozen_string_literal: true

module Nu
  module Agent
    module Tools
      class ManIndexer
        def name
          "man_indexer"
        end

        def description
          "Check the status of background man page indexing. " \
          "Returns progress information including how many man pages have been indexed, " \
          "how many failed or were skipped, current batch being processed, and costs."
        end

        def parameters
          {} # No parameters needed
        end

        def execute(arguments:, history:, context:)
          # Debug output
          if application = context['application']
            application.output.debug("[man_indexer] checking status")
          end

          # Get the Application instance from context
          application = context['application']

          if application.nil?
            return {
              'error' => 'Application context not available'
            }
          end

          # Get enabled status
          enabled = history.get_config('index_man_enabled') == 'true'

          # Read status under mutex
          status = nil
          application.status_mutex.synchronize do
            status = application.man_indexer_status.dup
          end

          # Format the response
          result = {
            'enabled' => enabled
          }

          if status['running']
            result.merge!({
              'running' => true,
              'progress' => {
                'total' => status['total'],
                'completed' => status['completed'],
                'failed' => status['failed'],
                'skipped' => status['skipped'],
                'remaining' => status['total'] - status['completed']
              },
              'session' => {
                'spend' => status['session_spend'],
                'tokens' => status['session_tokens']
              },
              'current_batch' => status['current_batch']
            })
          elsif status['total'] > 0
            # Has run or is idle
            result.merge!({
              'running' => false,
              'progress' => {
                'total' => status['total'],
                'completed' => status['completed'],
                'failed' => status['failed'],
                'skipped' => status['skipped'],
                'remaining' => status['total'] - status['completed']
              },
              'session' => {
                'spend' => status['session_spend'],
                'tokens' => status['session_tokens']
              }
            })
          else
            # Never started
            result.merge!({
              'running' => false,
              'message' => 'Man page indexing not yet started'
            })
          end

          result
        end
      end
    end
  end
end
