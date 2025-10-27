# frozen_string_literal: true

module Nu
  module Agent
    # Manages lifecycle of a worker token to prevent double-increment/decrement bugs
    class WorkerToken
      def initialize(history)
        @history = history
        @active = false
        @mutex = Mutex.new
      end

      # Activate the worker token (increment counter)
      # Safe to call multiple times - only increments once
      def activate
        @mutex.synchronize do
          return if @active

          @history.increment_workers
          @active = true
        end
      end

      # Release the worker token (decrement counter)
      # Safe to call multiple times - only decrements once
      def release
        @mutex.synchronize do
          return unless @active

          @history.decrement_workers
          @active = false
        end
      end

      def active?
        @mutex.synchronize { @active }
      end
    end
  end
end
