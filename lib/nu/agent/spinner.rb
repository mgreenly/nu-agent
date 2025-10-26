# frozen_string_literal: true

module Nu
  module Agent
    class Spinner
      FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"].freeze
      FRAME_INTERVAL = 0.1 # seconds

      def initialize(message = "")
        @message = message
        @running = false
        @thread = nil
        @mutex = Mutex.new
        @start_time = nil
      end

      def start(message = nil, start_time: nil)
        @mutex.synchronize do
          return if @running

          @message = message if message
          @start_time = start_time if start_time
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

        # Calculate elapsed time if start_time is set
        message_with_time = @message
        if @start_time
          elapsed = Time.now - @start_time
          time_str = format_elapsed_time(elapsed)
          message_with_time = "#{@message} (#{time_str})"
        end

        # Use carriage return to overwrite the line
        # Light blue color: \e[94m ... \e[0m
        print "\r\e[94m#{frame} #{message_with_time}\e[0m"
        $stdout.flush
      end

      def format_elapsed_time(seconds)
        if seconds < 60
          # Less than a minute: show seconds with 1 decimal
          "#{'%.1f' % seconds}s"
        elsif seconds < 3600
          # Less than an hour: show minutes and seconds
          mins = (seconds / 60).to_i
          secs = (seconds % 60).to_i
          "#{mins}m #{secs}s"
        else
          # An hour or more: show hours and minutes
          hours = (seconds / 3600).to_i
          mins = ((seconds % 3600) / 60).to_i
          "#{hours}h #{mins}m"
        end
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
