# frozen_string_literal: true

module Nu
  module Agent
    # Manages worker thread counting for background operations
    class WorkerCounter
      def initialize(config_store)
        @config_store = config_store
      end

      def increment_workers
        current = current_workers
        new_value = current + 1
        @config_store.set_config("active_workers", new_value)
      end

      def decrement_workers
        current = current_workers
        new_value = [current - 1, 0].max
        @config_store.set_config("active_workers", new_value)
      end

      def workers_idle?
        current_workers.zero?
      end

      private

      def current_workers
        value = @config_store.get_config("active_workers")
        value ? value.to_i : 0
      end
    end
  end
end
