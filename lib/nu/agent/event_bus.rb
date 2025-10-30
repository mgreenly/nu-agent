# frozen_string_literal: true

module Nu
  module Agent
    # Thread-safe event bus for pub/sub message passing
    # Replaces polling with event-driven architecture
    class EventBus
      def initialize
        @subscribers = {}
        @mutex = Mutex.new
      end

      # Subscribe to an event type
      # @param event_type [Symbol] the event type to subscribe to
      # @yield [data] callback to execute when event is published
      # @return [Proc] the callback for later unsubscription
      def subscribe(event_type, &block)
        raise ArgumentError, "Block required for subscription" unless block

        @mutex.synchronize do
          @subscribers[event_type] ||= []
          @subscribers[event_type] << block
        end

        block
      end

      # Unsubscribe from an event type
      # @param event_type [Symbol] the event type
      # @param callback [Proc] the callback to remove
      def unsubscribe(event_type, callback)
        @mutex.synchronize do
          return unless @subscribers[event_type]

          @subscribers[event_type].delete(callback)
        end
      end

      # Publish an event to all subscribers
      # @param event_type [Symbol] the event type
      # @param data [Object] the event data
      def publish(event_type, data = nil)
        callbacks = @mutex.synchronize do
          @subscribers[event_type]&.dup || []
        end

        callbacks.each do |callback|
          callback.call(data)
        rescue StandardError => e
          # Log error but continue processing other callbacks
          warn "EventBus: Error in subscriber callback: #{e.message}"
        end
      end

      # Clear all subscribers
      def clear
        @mutex.synchronize { @subscribers.clear }
      end

      # Get total subscriber count across all event types
      # @return [Integer] total number of subscribers
      def subscriber_count
        @mutex.synchronize do
          @subscribers.values.sum(&:length)
        end
      end

      # Check if event type has any subscribers
      # @param event_type [Symbol] the event type to check
      # @return [Boolean] true if subscribers exist
      def subscribers?(event_type)
        @mutex.synchronize do
          !@subscribers[event_type].nil? && !@subscribers[event_type].empty?
        end
      end
    end
  end
end
