# frozen_string_literal: true

module Nu
  module Agent
    class Spinner
      FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'].freeze
      FRAME_INTERVAL = 0.1 # seconds

      def initialize(message = "")
        @message = message
        @running = false
        @thread = nil
        @mutex = Mutex.new
      end

      def start(message = nil)
        @mutex.synchronize do
          return if @running

          @message = message if message
          @running = true
          @frame_index = 0

          @thread = Thread.new do
            while @running
              draw_frame
              sleep FRAME_INTERVAL
              @frame_index = (@frame_index + 1) % FRAMES.length
            end
          end
        end
      end

      def stop
        @mutex.synchronize do
          return unless @running

          @running = false
          @thread&.join
          @thread = nil
          clear_line
        end
      end

      def update_message(message)
        @mutex.synchronize do
          @message = message
        end
      end

      private

      def draw_frame
        return unless @running

        frame = FRAMES[@frame_index]
        # Use carriage return to overwrite the line
        # Light blue color: \e[94m ... \e[0m
        print "\r\e[94m#{frame} #{@message}\e[0m"
        $stdout.flush
      end

      def clear_line
        # Clear the spinner line using ANSI escape codes
        # \r moves to start of line, \e[K clears from cursor to end of line
        print "\r\e[K"
        $stdout.flush
      end
    end
  end
end
