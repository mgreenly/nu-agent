# frozen_string_literal: true

require 'curses'
require 'io/console'

module Nu
  module Agent
    class TUIManager
      attr_reader :active

      def initialize
        @mutex = Mutex.new
        @output_buffer = []
        @input_buffer = String.new  # Mutable string
        @cursor_pos = 0
        @active = false

        begin
          # Check if we can use curses
          unless $stdout.tty?
            raise "Not a TTY"
          end

          # Initialize curses
          Curses.init_screen
          Curses.start_color
          Curses.cbreak
          Curses.noecho
          Curses.curs_set(1) # Show cursor

          # Get screen dimensions
          @screen_height = Curses.lines
          @screen_width = Curses.cols

          # Check minimum size
          if @screen_height < 10 || @screen_width < 40
            Curses.close_screen
            raise "Terminal too small (minimum 10x40)"
          end

          # Calculate pane sizes (80/20 split)
          @output_height = (@screen_height * 0.8).to_i
          @input_height = @screen_height - @output_height - 1 # -1 for separator

          # Create windows
          @output_win = Curses::Window.new(@output_height, @screen_width, 0, 0)
          @separator_win = Curses::Window.new(1, @screen_width, @output_height, 0)
          @input_win = Curses::Window.new(@input_height, @screen_width, @output_height + 1, 0)

          # Configure output window for scrolling
          @output_win.scrollok(true)
          @output_win.idlok(true)

          # Configure input window
          @input_win.scrollok(false)
          @input_win.keypad(true) # Enable arrow keys, etc.
          @input_win.nodelay(false) # Wait for input (blocking mode)

          # Initialize color pairs
          Curses.init_pair(1, Curses::COLOR_RED, Curses::COLOR_BLACK)     # Error
          Curses.init_pair(2, Curses::COLOR_WHITE, Curses::COLOR_BLACK)   # Normal
          Curses.init_pair(3, Curses::COLOR_BLACK, Curses::COLOR_WHITE)   # Separator

          # Draw separator
          draw_separator

          # Initial refresh
          @output_win.refresh
          @separator_win.refresh
          @input_win.refresh

          @active = true

        rescue => e
          # Clean up if initialization failed
          Curses.close_screen rescue nil
          raise "Failed to initialize TUI: #{e.message}"
        end
      end

      def write_output(text, color: :normal)
        return unless @active

        @mutex.synchronize do
          # Strip ANSI color codes
          clean_text = text.to_s.gsub(/\e\[[0-9;]*m/, '')

          # Split text into lines
          lines = clean_text.split("\n")

          lines.each do |line|
            # Store in buffer for scrollback
            @output_buffer << line

            # Trim buffer if too large (keep last 1000 lines)
            @output_buffer.shift if @output_buffer.length > 1000

            # Write to window with color
            case color
            when :error
              @output_win.attron(Curses.color_pair(1)) do
                write_line_to_output(line)
              end
            when :debug
              # Gray color for debug (we'll use dim attribute since we only have 3 color pairs)
              @output_win.attron(Curses::A_DIM) do
                write_line_to_output(line)
              end
            else
              @output_win.attron(Curses.color_pair(2)) do
                write_line_to_output(line)
              end
            end
          end

          @output_win.refresh
        end
      end

      def write_debug(text)
        # Strip any existing ANSI codes
        clean_text = text.gsub(/\e\[[0-9;]*m/, '')
        write_output(clean_text, color: :debug)
      end

      def write_error(text)
        # Strip any existing ANSI codes
        clean_text = text.gsub(/\e\[[0-9;]*m/, '')
        write_output(clean_text, color: :error)
      end

      def readline(prompt = "> ")
        return nil unless @active

        @input_buffer = String.new  # Mutable string
        @cursor_pos = 0

        # Draw prompt and clear input area
        @input_win.clear
        @input_win.setpos(0, 0)
        @input_win.addstr(prompt)
        @input_win.setpos(0, prompt.length) # Position cursor after prompt
        @input_win.refresh

        loop do
          ch = @input_win.getch

          # Handle string vs integer from getch
          if ch.is_a?(String)
            # Some curses implementations return strings directly
            if ch == "\n" || ch == "\r"
              line = @input_buffer.dup
              @input_buffer = String.new  # Mutable string
              @cursor_pos = 0
              return line
            elsif ch == "\u007F" || ch == "\b" # Backspace
              if @cursor_pos > 0
                @input_buffer.slice!(@cursor_pos - 1)
                @cursor_pos -= 1
                redraw_input(prompt)
              end
            elsif ch == "\u0003" # Ctrl-C
              raise Interrupt
            elsif ch == "\u0004" # Ctrl-D
              return nil if @input_buffer.empty?
            elsif ch.ord >= 32 && ch.ord <= 126 # Printable
              @input_buffer.insert(@cursor_pos, ch)
              @cursor_pos += 1
              redraw_input(prompt)
            end
          else
            # Integer codes
            case ch
            when 10, 13 # Enter
              line = @input_buffer.dup
              @input_buffer = String.new  # Mutable string
              @cursor_pos = 0
              return line

            when 127, 8, Curses::KEY_BACKSPACE # Backspace (various codes)
              if @cursor_pos > 0
                @input_buffer.slice!(@cursor_pos - 1)
                @cursor_pos -= 1
                redraw_input(prompt)
              end

            when Curses::KEY_DC # Delete
              if @cursor_pos < @input_buffer.length
                @input_buffer.slice!(@cursor_pos)
                redraw_input(prompt)
              end

            when Curses::KEY_LEFT
              @cursor_pos = [@cursor_pos - 1, 0].max
              update_cursor(prompt)

            when Curses::KEY_RIGHT
              @cursor_pos = [@cursor_pos + 1, @input_buffer.length].min
              update_cursor(prompt)

            when Curses::KEY_HOME
              @cursor_pos = 0
              update_cursor(prompt)

            when Curses::KEY_END
              @cursor_pos = @input_buffer.length
              update_cursor(prompt)

            when 3 # Ctrl-C
              raise Interrupt

            when 4 # Ctrl-D
              return nil if @input_buffer.empty?

            when 32..126 # Printable characters
              char = ch.chr
              @input_buffer.insert(@cursor_pos, char)
              @cursor_pos += 1
              redraw_input(prompt)

            when Curses::KEY_RESIZE
              handle_resize
              redraw_input(prompt)
            end
          end
        end
      end

      def close
        return unless @active

        @mutex.synchronize do
          @active = false
          Curses.close_screen
        end
      end

      private

      def write_line_to_output(line)
        # Handle long lines by wrapping
        if line.length > @screen_width
          line.scan(/.{1,#{@screen_width}}/).each do |chunk|
            @output_win.addstr(chunk + "\n")
          end
        else
          @output_win.addstr(line + "\n")
        end
      end

      def draw_separator
        @separator_win.attron(Curses.color_pair(3)) do
          @separator_win.setpos(0, 0)
          @separator_win.addstr("─" * @screen_width)
        end
        @separator_win.refresh
      end

      def redraw_input(prompt)
        @input_win.clear
        @input_win.setpos(0, 0)
        @input_win.addstr(prompt)
        @input_win.addstr(@input_buffer)
        # Position cursor
        cursor_x = prompt.length + @cursor_pos
        @input_win.setpos(0, cursor_x)
        @input_win.refresh
      end

      def update_cursor(prompt)
        cursor_x = prompt.length + @cursor_pos
        @input_win.setpos(0, cursor_x)
        @input_win.refresh
      end

      def handle_resize
        # Get new screen dimensions
        Curses.update_screen_size
        @screen_height = Curses.lines
        @screen_width = Curses.cols

        # Recalculate pane sizes
        @output_height = (@screen_height * 0.8).to_i
        @input_height = @screen_height - @output_height - 1

        # Recreate windows
        @output_win.close
        @separator_win.close
        @input_win.close

        @output_win = Curses::Window.new(@output_height, @screen_width, 0, 0)
        @separator_win = Curses::Window.new(1, @screen_width, @output_height, 0)
        @input_win = Curses::Window.new(@input_height, @screen_width, @output_height + 1, 0)

        # Reconfigure
        @output_win.scrollok(true)
        @output_win.idlok(true)
        @input_win.scrollok(false)
        @input_win.keypad(true)

        # Redraw everything
        redraw_output_buffer
        draw_separator
        @output_win.refresh
        @separator_win.refresh
      end

      def redraw_output_buffer
        @output_win.clear
        # Show last N lines that fit in window
        visible_lines = @output_buffer.last(@output_height - 1)
        visible_lines.each do |line|
          write_line_to_output(line)
        end
      end
    end
  end
end
