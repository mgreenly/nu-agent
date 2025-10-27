# frozen_string_literal: true

module Nu
  module Agent
    # Encapsulates spinner state to reduce scattered state management
    class SpinnerState
      attr_accessor :running, :message, :frame, :parent_thread, :interrupt_requested

      def initialize
        @running = false
        @message = ""
        @frame = 0
        @parent_thread = nil
        @interrupt_requested = false
      end

      def active?
        @running && !@parent_thread.nil?
      end

      def reset
        @running = false
        @parent_thread = nil
        @interrupt_requested = false
        @message = ""
        @frame = 0
      end

      def start(message, parent_thread)
        @running = true
        @message = message
        @frame = 0
        @parent_thread = parent_thread
        @interrupt_requested = false
      end

      def stop
        @running = false
      end
    end
  end
end
