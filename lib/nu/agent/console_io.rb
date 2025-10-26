# frozen_string_literal: true

require "io/console"

module Nu
  module Agent
    # ConsoleIO - Unified console I/O system with raw terminal mode and IO.select
    # Replaces TUIManager, OutputManager, and OutputBuffer with a single class
    class ConsoleIO
      def initialize
        @stdin = $stdin
        @stdout = $stdout

        # Save original terminal state
        @original_stty = `stty -g`.chomp

        # Set up raw mode
        setup_terminal

        # Output queue with signaling
        @output_queue = Queue.new
        @output_pipe_read, @output_pipe_write = IO.pipe
        @mutex = Mutex.new

        # Input state
        @input_buffer = ""
        @cursor_pos = 0
        @kill_ring = ""
        @history = []
        @history_pos = nil
        @saved_input = ""

        # Spinner state
        @spinner_running = false
        @spinner_thread = nil
        @spinner_frame = 0
        @spinner_frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        @spinner_message = ""

        # Mode tracking
        @mode = :input # :input or :spinner

        # Register cleanup
        at_exit { restore_terminal }
      end

      # Thread-safe output from background threads
      def puts(text)
        @output_queue.push(text)
        @output_pipe_write.write("x") # Signal select loop
      rescue StandardError
        # Ignore if pipe closed
      end

      # Spinner mode - show animated spinner
      def show_spinner(message)
        @mode = :spinner
        @spinner_message = message
        @spinner_frame = 0
        @spinner_running = true

        # Flush stdin before starting spinner
        flush_stdin

        @spinner_thread = Thread.new do
          spinner_loop
        rescue Interrupt
          hide_spinner
          raise
        end
      end

      # Hide spinner and return to ready state
      def hide_spinner
        @spinner_running = false
        @spinner_thread&.join

        @mutex.synchronize do
          @stdout.write("\e[2K\r") # Clear spinner line
          @stdout.flush
        end

        # Flush stdin when returning to input mode
        flush_stdin
      end

      # Blocking read with interruption support
      def readline(prompt)
        @mode = :input
        @input_buffer = ""
        @cursor_pos = 0
        @history_pos = nil
        @saved_input = ""

        redraw_input_line(prompt)

        loop do
          result = handle_readline_select(prompt)
          return result if result
        end
      end

      # Cleanup
      def close
        return unless @original_stty

        restore_terminal
      end

      private

      def handle_readline_select(prompt)
        # Monitor stdin and output pipe
        readable, = IO.select([@stdin, @output_pipe_read], nil, nil)

        readable.each do |io|
          if io == @output_pipe_read
            # Background output arrived
            handle_output_for_input_mode(prompt)
          elsif io == @stdin
            # User input arrived
            result = handle_stdin_input(prompt)
            return result if result
          end
        end

        nil
      end

      def handle_stdin_input(prompt)
        raw = @stdin.read_nonblock(1024)
        result = parse_input(raw)

        case result
        when :submit
          submit_input(prompt)
        when :eof
          handle_eof
        else
          redraw_input_line(prompt)
          nil
        end
      end

      def submit_input(prompt)
        line = @input_buffer.dup

        @mutex.synchronize do
          @stdout.write("\e[2K\r")
          @stdout.write(prompt)
          @stdout.puts(line)
        end

        add_to_history(line)
        line
      end

      def handle_eof
        @mutex.synchronize do
          @stdout.write("\e[2K\r")
          @stdout.flush
        end
        nil
      end

      def setup_terminal
        # Enter raw mode (no echo, no line buffering)
        @stdin.raw!
      end

      def restore_terminal
        return unless @original_stty

        # Restore original state
        system("stty #{@original_stty}")

        # Show cursor
        @stdout.write("\e[?25h")
        @stdout.flush
      end

      def drain_output_queue
        lines = []

        # Drain pipe signals
        begin
          @output_pipe_read.read_nonblock(1024)
        rescue IO::WaitReadable, EOFError
          # Empty
        end

        # Drain queue
        loop do
          lines << @output_queue.pop(true)
        rescue ThreadError
          break # Queue empty
        end

        lines
      end

      def parse_input(raw)
        raw.each_char do |char|
          case char
          when "\r", "\n"
            # Enter pressed
            return :submit

          when "\x03" # Ctrl-C
            raise Interrupt

          when "\x04" # Ctrl-D
            return :eof if @input_buffer.empty?

          when "\x7F", "\b" # Backspace
            delete_backward

          else
            # Printable character
            insert_char(char) if char.ord.between?(32, 126)
          end
        end

        nil # Continue reading
      end

      def insert_char(char)
        @input_buffer.insert(@cursor_pos, char)
        @cursor_pos += 1
      end

      def delete_backward
        return if @cursor_pos.zero?

        @input_buffer.slice!(@cursor_pos - 1)
        @cursor_pos -= 1
      end

      def redraw_input_line(prompt)
        @mutex.synchronize do
          # Clear line
          @stdout.write("\e[2K\r")

          # Redraw prompt and buffer
          @stdout.write(prompt)
          @stdout.write(@input_buffer)

          # Position cursor
          # Formula: prompt.length + @cursor_pos + 1 (1-indexed)
          col = prompt.length + @cursor_pos + 1
          @stdout.write("\e[#{col}G")

          @stdout.flush
        end
      end

      def handle_output_for_input_mode(prompt)
        lines = drain_output_queue
        return if lines.empty?

        @mutex.synchronize do
          # Clear current input line
          @stdout.write("\e[2K\r")

          # Write all output (with ANSI colors preserved)
          lines.each { |line| @stdout.puts(line) }

          # Redraw input line at new bottom
          @stdout.write(prompt)
          @stdout.write(@input_buffer)

          col = prompt.length + @cursor_pos + 1
          @stdout.write("\e[#{col}G")

          @stdout.flush
        end
      end

      def add_to_history(line)
        # Don't add empty lines or duplicates of last entry
        return if line.strip.empty?
        return if !@history.empty? && @history.last == line

        @history << line
      end

      def flush_stdin
        # Drain all buffered input
        loop do
          break unless @stdin.wait_readable(0)

          @stdin.read_nonblock(1024)
        rescue IO::WaitReadable
          break
        end
      end

      def spinner_loop
        loop do
          break unless @spinner_running

          # Check for output or Ctrl-C with 100ms timeout
          readable, = IO.select([@stdin, @output_pipe_read], nil, nil, 0.1)

          if readable
            readable.each do |io|
              if io == @output_pipe_read
                # Background output arrived
                handle_output_for_spinner_mode
              elsif io == @stdin
                # Check for Ctrl-C
                char = @stdin.read_nonblock(1)
                if char == "\x03"
                  @spinner_running = false
                  flush_stdin
                  raise Interrupt
                end
                # Ignore other keystrokes
              end
            end
          else
            # Timeout - animate spinner
            animate_spinner
          end
        rescue IO::WaitReadable
          # Ignore
        end
      end

      def handle_output_for_spinner_mode
        lines = drain_output_queue
        return if lines.empty?

        @mutex.synchronize do
          # Clear spinner line
          @stdout.write("\e[2K\r")

          # Write all output
          lines.each { |line| @stdout.puts(line) }

          # Redraw spinner at new bottom
          frame = @spinner_frames[@spinner_frame]
          @stdout.write("#{frame} #{@spinner_message}")

          @stdout.flush
        end
      end

      def animate_spinner
        @spinner_frame = (@spinner_frame + 1) % @spinner_frames.length
        redraw_spinner
      end

      def redraw_spinner
        @mutex.synchronize do
          @stdout.write("\e[2K\r")
          frame = @spinner_frames[@spinner_frame]
          @stdout.write("#{frame} #{@spinner_message}")
          @stdout.flush
        end
      end
    end
  end
end
