# frozen_string_literal: true

require "io/console"
require_relative "console_io_states"

module Nu
  module Agent
    # ConsoleIO - Unified console I/O system with raw terminal mode and IO.select
    # Replaces TUIManager, OutputManager, and OutputBuffer with a single class
    # Uses State Pattern for clean state management and transitions
    class ConsoleIO
      attr_reader :state
      attr_writer :debug

      def initialize(db_history: nil, debug: false)
        @stdin = $stdin
        @stdout = $stdout
        @debug = debug

        # Save original terminal state
        @original_stty = `stty -g`.chomp

        # Set up raw mode
        setup_terminal

        # Output queue with signaling
        @output_queue = Queue.new
        @output_pipe_read, @output_pipe_write = IO.pipe
        @mutex = Mutex.new

        # Input state
        @input_buffer = String.new("")
        @cursor_pos = 0
        @kill_ring = String.new("")
        @history = []
        @history_pos = nil
        @saved_input = String.new("")

        # Database history (optional)
        @db_history = db_history
        load_history_from_db if @db_history

        # Spinner state (encapsulated)
        @spinner_state = SpinnerState.new
        @spinner_thread = nil
        @spinner_frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

        # State Pattern - replaces @mode
        @state = IdleState.new(self)
        @previous_state = nil

        # Register cleanup
        at_exit { restore_terminal }
      end

      # State management methods

      # Get current state object
      def current_state
        @state
      end

      # Get current state name for debugging
      def current_state_name
        @state.name
      end

      # Transition to a new state
      def transition_to(new_state)
        return if @state == new_state

        log_state_transition(@state, new_state) if @debug

        @state.on_exit
        @previous_state = @state
        @state = new_state
        @state.on_enter
      end

      # Pause (can be called from any state)
      def pause
        @state.pause
      end

      # Resume from paused state
      def resume
        raise StateTransitionError, "Not in paused state" unless @state.is_a?(PausedState)

        @state.resume
      end

      # Thread-safe output from background threads
      def puts(text)
        @output_queue.push(text)
        @output_pipe_write.write("x") # Signal select loop
      rescue StandardError
        # Ignore if pipe closed
      end

      # Progress bar methods - delegate to state

      def start_progress
        @state.start_progress
      end

      def update_progress(text)
        @state.update_progress(text)
      end

      def end_progress
        @state.end_progress
      end

      # Internal methods called by states (prefixed with do_)

      def do_start_progress
        @mutex.synchronize do
          @stdout.write("\e[2K\r") # Clear line and return to start
          @stdout.flush
        end
      end

      def do_update_progress(text)
        @mutex.synchronize do
          @stdout.write("\r#{text}")
          @stdout.flush
        end
      rescue StandardError
        # Ignore if output fails
      end

      def do_end_progress
        @mutex.synchronize do
          @stdout.write("\r\n") # Move to next line, keeping progress visible
          @stdout.flush
        end
      end

      # Spinner methods - delegate to state

      def show_spinner(message)
        @state.show_spinner(message)
      end

      def hide_spinner
        @state.hide_spinner
      end

      # Internal methods called by states

      def do_show_spinner(message)
        @spinner_state.start(message, Thread.current)
        flush_stdin

        @spinner_thread = Thread.new do
          Thread.current.report_on_exception = false
          spinner_loop
        rescue Interrupt
          @mutex.synchronize do
            @stdout.write("\e[2K\r")
            @stdout.flush
          end
          @spinner_state.interrupt_requested = true
          @spinner_state.parent_thread&.raise(Interrupt)
        end
      end

      def do_hide_spinner
        @spinner_state.stop
        @spinner_thread&.join unless Thread.current == @spinner_thread

        @mutex.synchronize do
          @stdout.write("\e[2K\r")
          @stdout.flush
        end

        flush_stdin
      end

      def update_spinner_message(message)
        @spinner_state.message = message
      end

      # Check if user requested interrupt via Ctrl-C
      def interrupt_requested?
        @spinner_state.interrupt_requested
      end

      # Blocking read with interruption support - delegates to state
      def readline(prompt)
        @state.readline(prompt)
      end

      # Internal readline implementation called by state
      def do_readline(prompt)
        @input_buffer = String.new("")
        @cursor_pos = 0
        @history_pos = nil
        @saved_input = String.new("")

        redraw_input_line(prompt)

        loop do
          result = handle_readline_select(prompt)

          next unless result != :continue

          # Input completed - notify state to transition back
          @state.on_input_completed if @state.respond_to?(:on_input_completed)
          return result
        end
      end

      # Cleanup
      def close
        return unless @original_stty

        restore_terminal
      end

      private

      # Multiline editing support - Line/column calculation helpers

      # Split input buffer into array of lines
      # Uses split("\n", -1) to preserve trailing empty line
      # Special case: empty buffer returns [""] for consistency
      def lines
        return [""] if @input_buffer.empty?

        @input_buffer.split("\n", -1)
      end

      # Convert byte position to [line_index, column_offset]
      # Clamps position to buffer length if beyond
      # Returns [0, 0] for empty buffer
      def get_line_and_column(pos)
        # Clamp position to buffer length
        pos = [@input_buffer.length, pos].min

        # Handle empty buffer
        return [0, 0] if @input_buffer.empty?

        # Iterate through lines to find position
        line_list = lines
        cumulative_pos = 0

        line_list.each_with_index do |line, line_index|
          line_length = line.length
          # Add 1 for newline character (except for last line)
          line_with_newline = line_index < line_list.length - 1 ? line_length + 1 : line_length

          # Position is on this line if it's within the line's range
          # For the last line, accept position at line_length (end of buffer)
          if pos <= cumulative_pos + line_length
            column = pos - cumulative_pos
            return [line_index, column]
          end

          cumulative_pos += line_with_newline
        end

        # Position is at the very end after all lines processed
        # This handles the case where pos == buffer.length and buffer ends without newline
        [line_list.length - 1, line_list.last.length]
      end

      # Convert [line_index, column_offset] to byte position
      # Clamps line to last line and column to line length
      # Returns position as integer
      def get_position_from_line_column(line, col)
        line_list = lines

        # Clamp line to valid range [0, last_line]
        line = line.clamp(0, line_list.length - 1)

        # Sum lengths of all lines before target line (including their newlines)
        pos = 0
        line.times do |i|
          pos += line_list[i].length + 1 # +1 for newline character
        end

        # Clamp column to target line's length
        target_line = line_list[line]
        col = col.clamp(0, target_line.length)

        pos + col
      end

      def log_state_transition(old_state, new_state)
        old_name = old_state.name
        new_name = new_state.name
        puts("\e[90m[ConsoleIO] State transition: #{old_name} -> #{new_name}\e[0m")
      end

      def handle_readline_select(prompt)
        # Monitor stdin and output pipe
        readable, = IO.select([@stdin, @output_pipe_read], nil, nil)

        return :continue if readable.nil?

        readable.each do |io|
          if io == @output_pipe_read
            # Background output arrived
            handle_output_for_input_mode(prompt)
          elsif io == @stdin
            # User input arrived
            result = handle_stdin_input(prompt)
            return result unless result == :continue
          end
        end

        :continue
      end

      def handle_stdin_input(prompt)
        raw = @stdin.read_nonblock(1024)
        result = parse_input(raw)

        case result
        when :submit
          submit_input(prompt)
        when :eof
          handle_eof
        when :clear_screen
          clear_screen(prompt)
          :continue
        else
          redraw_input_line(prompt)
          :continue
        end
      end

      def submit_input(prompt)
        line = @input_buffer.dup

        @mutex.synchronize do
          @stdout.write("\e[2K\r")
          @stdout.write(prompt)
          @stdout.write("#{line}\r\n") # In raw mode, need explicit \r\n
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
        chars = raw.chars
        i = 0

        while i < chars.length
          char = chars[i]

          case char
          when "\r", "\n"
            # Enter pressed
            return :submit

          when "\x03" # Ctrl-C
            raise Interrupt

          when "\x04" # Ctrl-D
            delete_forward

          when "\x7F", "\b" # Backspace
            delete_backward

          when "\x01" # Ctrl-A
            cursor_to_start

          when "\x05" # Ctrl-E
            cursor_to_end

          when "\x0B" # Ctrl-K
            kill_to_end

          when "\x15" # Ctrl-U
            kill_to_start

          when "\x17" # Ctrl-W
            kill_word_backward

          when "\x19" # Ctrl-Y
            yank

          when "\x0C" # Ctrl-L
            return :clear_screen

          when "\e" # Escape - start of sequence
            i = handle_escape_sequence(chars, i)

          else
            # Printable character
            insert_char(char) if char.ord.between?(32, 126)
          end

          i += 1
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

      def delete_forward
        return if @cursor_pos >= @input_buffer.length

        @input_buffer.slice!(@cursor_pos)
      end

      def handle_escape_sequence(chars, index)
        # Check if we have enough characters for a sequence
        return index if index + 1 >= chars.length

        next_char = chars[index + 1]

        # Check for CSI sequences (Control Sequence Introducer)
        return handle_csi_sequence(chars, index + 2) if next_char == "["

        index + 1
      end

      def handle_csi_sequence(chars, index)
        return index - 1 if index >= chars.length

        char = chars[index]

        case char
        when "A" # Up arrow - navigate history backward
          history_prev
          index
        when "B" # Down arrow - navigate history forward
          history_next
          index
        when "C" # Right arrow
          cursor_forward
          index
        when "D" # Left arrow
          cursor_backward
          index
        when "H" # Home
          cursor_to_start
          index
        when "F" # End
          cursor_to_end
          index
        when "1" # Home variant (1~)
          if index + 1 < chars.length && chars[index + 1] == "~"
            cursor_to_start
            index + 1
          else
            index
          end
        when "3" # Delete (3~)
          if index + 1 < chars.length && chars[index + 1] == "~"
            delete_forward
            index + 1
          else
            index
          end
        when "4" # End variant (4~)
          if index + 1 < chars.length && chars[index + 1] == "~"
            cursor_to_end
            index + 1
          else
            index
          end
        else
          # Unknown sequence - ignore
          index
        end
      end

      def cursor_forward
        return if @cursor_pos >= @input_buffer.length

        @cursor_pos += 1
      end

      def cursor_backward
        return if @cursor_pos.zero?

        @cursor_pos -= 1
      end

      def cursor_to_start
        @cursor_pos = 0
      end

      def cursor_to_end
        @cursor_pos = @input_buffer.length
      end

      def kill_to_end
        return if @cursor_pos >= @input_buffer.length

        @kill_ring = @input_buffer[@cursor_pos..]
        @input_buffer.slice!(@cursor_pos..)
      end

      def kill_to_start
        return if @cursor_pos.zero?

        @kill_ring = @input_buffer[0...@cursor_pos]
        @input_buffer.slice!(0...@cursor_pos)
        @cursor_pos = 0
      end

      def kill_word_backward
        return if @cursor_pos.zero?

        # Find start of word by scanning backward
        pos = @cursor_pos - 1

        # Skip trailing whitespace if cursor is after whitespace
        pos -= 1 while pos >= 0 && @input_buffer[pos] =~ /\s/

        # Find start of word (scan back to whitespace or start)
        pos -= 1 while pos >= 0 && @input_buffer[pos] !~ /\s/

        # pos is now at the whitespace before the word, or -1 if at start
        start_pos = pos + 1

        # Kill from start_pos to cursor
        @kill_ring = @input_buffer[start_pos...@cursor_pos]
        @input_buffer.slice!(start_pos...@cursor_pos)
        @cursor_pos = start_pos
      end

      def yank
        return if @kill_ring.empty?

        @input_buffer.insert(@cursor_pos, @kill_ring)
        @cursor_pos += @kill_ring.length
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

      def clear_screen(prompt)
        @mutex.synchronize do
          # Clear screen and move cursor to home
          @stdout.write("\e[2J\e[H")

          # Redraw prompt and input buffer
          @stdout.write(prompt)
          @stdout.write(@input_buffer)

          # Position cursor
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

          # Write all output (in raw mode, need explicit \r\n for all newlines)
          lines.each do |line|
            # Replace any bare \n with \r\n for proper line breaks in raw mode
            formatted = line.gsub("\n", "\r\n")
            @stdout.write("#{formatted}\r\n")
          end

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
        save_history_to_db(line)
      end

      def save_history_to_db(command)
        return if command.nil? || command.strip.empty?
        return unless @db_history

        @db_history.add_command_history(command)
      rescue StandardError => e
        # Log error but don't fail - history is not critical
        warn "Warning: Failed to save command history: #{e.message}" if @debug
      end

      def load_history_from_db
        return unless @db_history

        history_records = @db_history.get_command_history(limit: 1000)
        @history = history_records.map { |record| record["command"] }
      rescue StandardError => e
        # Log error but don't fail - history is not critical
        warn "Warning: Failed to load command history: #{e.message}" if @debug
        @history = []
      end

      def history_prev
        if @history_pos.nil?
          # Starting from current input - save it and move to last history entry
          return if @history.empty?

          @saved_input = @input_buffer.dup
          @history_pos = @history.length - 1
        elsif @history_pos.positive?
          # Move backward in history
          @history_pos -= 1
        end

        @input_buffer = (@history[@history_pos] || "").dup
        @cursor_pos = @input_buffer.length
      end

      def history_next
        # Only move forward if we're in history
        return unless @history_pos

        @history_pos += 1

        if @history_pos >= @history.length
          # Reached end - restore saved input
          @input_buffer = @saved_input.dup
          @cursor_pos = @input_buffer.length
          @history_pos = nil
        else
          @input_buffer = @history[@history_pos].dup
          @cursor_pos = @input_buffer.length
        end
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
          break unless @spinner_state.running

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
                  @spinner_state.stop
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

          # Write all output (in raw mode, need explicit \r\n for all newlines)
          lines.each do |line|
            # Replace any bare \n with \r\n for proper line breaks in raw mode
            formatted = line.gsub("\n", "\r\n")
            @stdout.write("#{formatted}\r\n")
          end

          # Redraw spinner at new bottom
          frame = @spinner_frames[@spinner_state.frame]
          @stdout.write("#{frame} #{@spinner_state.message}")

          @stdout.flush
        end
      end

      def animate_spinner
        @spinner_state.frame = (@spinner_state.frame + 1) % @spinner_frames.length
        redraw_spinner
      end

      def redraw_spinner
        @mutex.synchronize do
          @stdout.write("\e[2K\r")
          frame = @spinner_frames[@spinner_state.frame]
          # Soft blue color (256-color palette: 81)
          @stdout.write("\e[38;5;81m#{frame} #{@spinner_state.message}\e[0m")
          @stdout.flush
        end
      end
    end
  end
end
