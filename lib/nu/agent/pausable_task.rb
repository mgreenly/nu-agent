# frozen_string_literal: true

module Nu
  module Agent
    # Base class for background workers that can be paused, resumed, and shut down cleanly
    class PausableTask
      def initialize(status_info:, shutdown_flag:)
        @status = status_info[:status]
        @status_mutex = status_info[:mutex]
        @shutdown_flag = shutdown_flag
        @pause_mutex = Mutex.new
        @pause_cv = ConditionVariable.new
        @paused = false
      end

      # Start the background worker thread
      # @return [Thread] The worker thread
      def start_worker
        Thread.new do
          Thread.current.report_on_exception = false
          run_worker_loop
        rescue StandardError
          @status_mutex.synchronize do
            @status["running"] = false
          end
        end
      end

      # Pause the worker thread
      def pause
        @pause_mutex.synchronize do
          @paused = true
          @status_mutex.synchronize do
            @status["paused"] = true
          end
        end
      end

      # Resume the worker thread
      def resume
        @pause_mutex.synchronize do
          @paused = false
          @status_mutex.synchronize do
            @status["paused"] = false
          end
          @pause_cv.broadcast
        end
      end

      # Wait until the task has paused (cooperative pausing)
      # @param timeout [Numeric] Maximum seconds to wait
      # @return [Boolean] true if paused within timeout, false otherwise
      def wait_until_paused(timeout: 5)
        deadline = Time.now + timeout
        was_ever_running = false

        loop do
          paused = @pause_mutex.synchronize { @paused }
          running = @status_mutex.synchronize { @status["running"] }

          was_ever_running = true if running

          # Only consider it paused if the pause flag is set AND it was running at some point
          return true if paused && was_ever_running

          remaining = deadline - Time.now
          return false if remaining <= 0

          sleep 0.1
        end
      end

      protected

      # Subclasses must implement this method to perform their specific work
      # This method will be called repeatedly in the worker loop
      def do_work
        raise NotImplementedError, "Subclasses must implement #do_work"
      end

      # Check if shutdown has been requested
      # @return [Boolean] true if shutdown requested
      def shutdown_requested?
        case @shutdown_flag
        when Hash
          @shutdown_flag[:value]
        else
          @shutdown_flag
        end
      end

      # Check and handle pause state - call this at safe checkpoints in work loops
      def check_pause
        @pause_mutex.synchronize do
          while @paused && !shutdown_requested?
            @pause_cv.wait(@pause_mutex, 0.1) # Wake up periodically to check shutdown
          end
        end
      end

      private

      def run_worker_loop
        loop do
          break if shutdown_requested?

          check_pause
          break if shutdown_requested?

          # Mark as running before doing work
          @status_mutex.synchronize do
            @status["running"] = true
          end

          do_work

          # Sleep between cycles to avoid busy-waiting (3 seconds total)
          # Check shutdown and pause every 200ms
          15.times do
            break if shutdown_requested?

            check_pause
            sleep 0.2
          end
        end
      ensure
        # Always mark as not running when exiting
        @status_mutex.synchronize do
          @status["running"] = false
          @status["paused"] = false
        end
      end
    end
  end
end
