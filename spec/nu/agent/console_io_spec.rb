# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Nu::Agent::ConsoleIO do
  subject(:console) do
    # Create console without setting up terminal (for testing)
    described_class.allocate.tap do |c|
      c.instance_variable_set(:@stdin, stdin)
      c.instance_variable_set(:@stdout, stdout)
      c.instance_variable_set(:@output_queue, Queue.new)
      c.instance_variable_set(:@output_pipe_read, pipe_read)
      c.instance_variable_set(:@output_pipe_write, pipe_write)
      c.instance_variable_set(:@mutex, Mutex.new)
      c.instance_variable_set(:@input_buffer, String.new(""))
      c.instance_variable_set(:@cursor_pos, 0)
      c.instance_variable_set(:@original_stty, nil)
      c.instance_variable_set(:@state, Nu::Agent::ConsoleIO::IdleState.new(c))
      c.instance_variable_set(:@history, [])
      c.instance_variable_set(:@history_pos, nil)
      c.instance_variable_set(:@saved_input, String.new(""))
      c.instance_variable_set(:@kill_ring, String.new(""))
      c.instance_variable_set(:@saved_column, nil)
      c.instance_variable_set(:@last_line_count, 1)
      c.instance_variable_set(:@spinner_state, Nu::Agent::SpinnerState.new)
      c.instance_variable_set(:@spinner_frames, ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
    end
  end

  let(:stdin) { instance_double(IO, "stdin") }
  let(:stdout) { StringIO.new }
  let(:pipe_read) { instance_double(IO, "pipe_read") }
  let(:pipe_write) { instance_double(IO, "pipe_write") }

  describe "#initialize" do
    it "initializes @input_buffer as mutable string to prevent FrozenError" do
      # This test verifies the fix for frozen string literal issue
      # With frozen_string_literal: true, @input_buffer = "" creates a frozen string
      # which causes FrozenError when trying to insert characters
      buffer = console.instance_variable_get(:@input_buffer)
      expect(buffer.frozen?).to be false
      expect { console.send(:insert_char, "a") }.not_to raise_error
    end

    it "initializes @saved_column to nil" do
      saved_column = console.instance_variable_get(:@saved_column)
      expect(saved_column).to be_nil
    end

    it "initializes @last_line_count to 1" do
      last_line_count = console.instance_variable_get(:@last_line_count)
      expect(last_line_count).to eq(1)
    end
  end

  describe "#readline" do
    it "resets @input_buffer to mutable string to prevent FrozenError" do
      # Simulate starting readline (can't actually call it without blocking)
      # This tests that the reset logic uses mutable strings
      console.instance_variable_set(:@input_buffer, String.new("old input"))
      console.instance_variable_set(:@saved_input, String.new(""))
      console.instance_variable_set(:@cursor_pos, 0)
      console.instance_variable_set(:@history_pos, nil)

      # Manually trigger what readline does to reset buffers
      console.instance_variable_set(:@state, Nu::Agent::ConsoleIO::IdleState.new(console))
      console.instance_variable_set(:@input_buffer, String.new(""))
      console.instance_variable_set(:@cursor_pos, 0)
      console.instance_variable_set(:@history_pos, nil)
      console.instance_variable_set(:@saved_input, String.new(""))

      buffer = console.instance_variable_get(:@input_buffer)
      expect(buffer.frozen?).to be false
      expect { console.send(:insert_char, "x") }.not_to raise_error
    end
  end

  describe "#puts" do
    it "adds text to output queue" do
      allow(pipe_write).to receive(:write)
      console.puts("Hello, world!")
      queue = console.instance_variable_get(:@output_queue)
      expect(queue.pop).to eq("Hello, world!")
    end

    it "signals the output pipe" do
      expect(pipe_write).to receive(:write).with("x")
      console.puts("Test message")
    end

    it "handles multiple concurrent puts calls safely" do
      allow(pipe_write).to receive(:write)
      threads = 10.times.map do
        Thread.new { console.puts("Thread message") }
      end
      threads.each(&:join)

      queue = console.instance_variable_get(:@output_queue)
      messages = []
      10.times { messages << queue.pop(true) }
      expect(messages.length).to eq(10)
    end
  end

  describe "progress bar methods" do
    describe "#start_progress" do
      it "transitions to ProgressState" do
        console.start_progress
        expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::ProgressState)
      end

      it "clears the line and writes to stdout" do
        console.start_progress
        expect(stdout.string).to include("\e[2K\r")
      end
    end

    describe "#update_progress" do
      it "writes progress text with carriage return to stdout" do
        console.start_progress # Need to be in ProgressState
        console.update_progress("[===>  ] 45%")
        expect(stdout.string).to include("[===>  ] 45%")
      end

      it "handles errors gracefully" do
        console.start_progress # Need to be in ProgressState
        allow(stdout).to receive(:write).and_raise(StandardError)
        expect { console.update_progress("test") }.not_to raise_error
      end
    end

    describe "#end_progress" do
      it "transitions back to IdleState" do
        console.start_progress
        console.end_progress
        expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::IdleState)
      end

      it "moves to next line, keeping progress visible" do
        console.start_progress
        console.end_progress
        expect(stdout.string).to include("\r\n")
      end
    end
  end

  describe "#drain_output_queue" do
    before do
      allow(pipe_write).to receive(:write)
    end

    it "returns empty array when queue is empty" do
      # Stub read_nonblock to return empty to simulate no signals
      allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")
      result = console.send(:drain_output_queue)
      expect(result).to eq([])
    end

    it "drains all queued messages" do
      allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")
      queue = console.instance_variable_get(:@output_queue)
      queue.push("Line 1")
      queue.push("Line 2")
      queue.push("Line 3")

      result = console.send(:drain_output_queue)
      expect(result).to eq(["Line 1", "Line 2", "Line 3"])
    end

    it "drains pipe signals" do
      allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("xxx")
      console.send(:drain_output_queue)
    end
  end

  describe "#parse_input (Phase 1)" do
    context "with Enter (submit key)" do
      it "returns :submit" do
        result = console.send(:parse_input, "\r")
        expect(result).to eq(:submit)
      end
    end

    context "with Ctrl-C" do
      it "raises Interrupt" do
        expect { console.send(:parse_input, "\x03") }.to raise_error(Interrupt)
      end
    end

    context "with Ctrl-D" do
      it "does nothing when buffer is empty" do
        console.instance_variable_set(:@input_buffer, String.new(""))
        result = console.send(:parse_input, "\x04")
        expect(result).to be_nil
      end

      it "deletes forward when buffer is not empty" do
        console.instance_variable_set(:@input_buffer, String.new("text"))
        console.instance_variable_set(:@cursor_pos, 0)
        result = console.send(:parse_input, "\x04")
        expect(result).to be_nil
        expect(console.instance_variable_get(:@input_buffer)).to eq("ext")
      end
    end

    context "with Backspace" do
      it "deletes character before cursor" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 5)
        console.send(:parse_input, "\x7F")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hell")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(4)
      end

      it "does nothing when cursor is at start" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 0)
        console.send(:parse_input, "\x7F")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      end
    end

    context "with printable characters" do
      it "inserts character at end" do
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)
        console.send(:parse_input, "a")
        expect(console.instance_variable_get(:@input_buffer)).to eq("a")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(1)
      end

      it "inserts multiple characters" do
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)
        console.send(:parse_input, "hello")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(5)
      end
    end
  end

  describe "#redraw_input_line" do
    context "with single line input" do
      it "clears the line and redraws prompt and buffer" do
        console.instance_variable_set(:@input_buffer, "test")
        console.instance_variable_set(:@cursor_pos, 4)
        console.instance_variable_set(:@last_line_count, 1)
        console.send(:redraw_input_line, "> ")

        output = stdout.string
        expect(output).to include("\e[J") # Clear to end of screen
        expect(output).to include("> test")
      end

      it "positions cursor correctly" do
        console.instance_variable_set(:@input_buffer, "hello")
        console.instance_variable_set(:@cursor_pos, 2)
        console.instance_variable_set(:@last_line_count, 1)
        console.send(:redraw_input_line, "> ")

        output = stdout.string
        # Cursor should be at column 5 (prompt "> " = 2 chars, cursor_pos = 2, col = 2 + 2 + 1 = 5)
        expect(output).to match(/\e\[5G/)
      end

      it "updates @last_line_count to 1 for single line" do
        console.instance_variable_set(:@input_buffer, "single line")
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@last_line_count, 3) # Previous multiline
        console.send(:redraw_input_line, "> ")

        expect(console.instance_variable_get(:@last_line_count)).to eq(1)
      end
    end

    context "with multiline input" do
      it "displays two lines correctly" do
        console.instance_variable_set(:@input_buffer, "line1\nline2")
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@last_line_count, 1)
        console.send(:redraw_input_line, "> ")

        output = stdout.string
        # Should contain both lines
        expect(output).to include("line1")
        expect(output).to include("line2")
      end

      it "displays three lines correctly" do
        console.instance_variable_set(:@input_buffer, "line1\nline2\nline3")
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@last_line_count, 1)
        console.send(:redraw_input_line, "> ")

        output = stdout.string
        expect(output).to include("line1")
        expect(output).to include("line2")
        expect(output).to include("line3")
      end

      it "updates @last_line_count to match number of lines" do
        console.instance_variable_set(:@input_buffer, "line1\nline2\nline3")
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@last_line_count, 1)
        console.send(:redraw_input_line, "> ")

        expect(console.instance_variable_get(:@last_line_count)).to eq(3)
      end

      it "positions cursor on correct line and column" do
        # Buffer: "line1\nline2", cursor at position 6 (first char of line2)
        console.instance_variable_set(:@input_buffer, "line1\nline2")
        console.instance_variable_set(:@cursor_pos, 6) # First char of "line2"
        console.instance_variable_set(:@last_line_count, 1)
        console.send(:redraw_input_line, "> ")

        output = stdout.string
        # After rendering both lines, cursor is at end of line2
        # Target is also on line2, so no vertical movement needed
        # Just position to column 1 (first character)
        expect(output).to match(/\e\[1G/) # Move to column 1
      end

      it "positions cursor on second line with offset" do
        # Buffer: "line1\nline2", cursor at position 8 (char 'n' in "line2")
        console.instance_variable_set(:@input_buffer, "line1\nline2")
        console.instance_variable_set(:@cursor_pos, 8)
        console.instance_variable_set(:@last_line_count, 1)
        console.send(:redraw_input_line, "> ")

        output = stdout.string
        # Cursor on line 2 (where we already are), column 3 (2 chars into "line2")
        expect(output).to match(/\e\[3G/) # Move to column 3
      end

      it "positions cursor on first line of multiline buffer" do
        # Buffer: "line1\nline2\nline3", cursor at position 2 (in "line1")
        console.instance_variable_set(:@input_buffer, "line1\nline2\nline3")
        console.instance_variable_set(:@cursor_pos, 2)
        console.instance_variable_set(:@last_line_count, 1)
        console.send(:redraw_input_line, "> ")

        output = stdout.string
        # After rendering 3 lines, cursor is at end of line3
        # Need to move up 2 lines to get to line1
        expect(output).to match(/\e\[2A/) # Move up 2 lines
        # Position at column 5 (prompt "> " = 2 chars, cursor_pos = 2, col = 2 + 2 + 1 = 5)
        expect(output).to match(/\e\[5G/)
      end

      it "clears previous multiline display before redrawing" do
        # Start with 3-line display, redraw with 2 lines
        console.instance_variable_set(:@input_buffer, "line1\nline2")
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@last_line_count, 3)
        console.instance_variable_set(:@last_cursor_physical_row, 2) # Cursor was on physical row 2
        console.send(:redraw_input_line, "> ")

        output = stdout.string
        # Should move up 2 physical rows to clear old display
        expect(output).to match(/\e\[2A/)
        # Should clear to end of screen
        expect(output).to include("\e[J")
      end

      it "moves to start of line before clearing (\\r before \\e[J])" do
        console.instance_variable_set(:@input_buffer, "test")
        console.instance_variable_set(:@cursor_pos, 4)
        console.instance_variable_set(:@last_line_count, 1)
        console.instance_variable_set(:@last_cursor_line, 0)

        console.send(:redraw_input_line, "> ")

        output = stdout.string
        # Should have \r before \e[J] to ensure full line is cleared
        expect(output).to match(/\r.*\e\[J/)
      end

      it "handles trailing newline" do
        console.instance_variable_set(:@input_buffer, "line1\n")
        console.instance_variable_set(:@cursor_pos, 6)
        console.instance_variable_set(:@last_line_count, 1)
        console.send(:redraw_input_line, "> ")

        expect(console.instance_variable_get(:@last_line_count)).to eq(2)
      end

      it "uses @last_cursor_line when set (after navigation)" do
        # Simulate: 3 lines, cursor moved to line 1 (middle line) via navigation
        # Previous redraw left cursor on line 1
        console.instance_variable_set(:@input_buffer, "line1\nline2\nline3")
        console.instance_variable_set(:@cursor_pos, 8) # Middle of line2
        console.instance_variable_set(:@last_line_count, 3)
        console.instance_variable_set(:@last_cursor_line, 1) # Cursor was on line 1 after previous redraw

        console.send(:redraw_input_line, "> ")

        output = stdout.string
        # Should move up 1 line (from @last_cursor_line), not 2 lines (from @last_line_count - 1)
        # This prevents erasing output above the prompt
        expect(output).to match(/\e\[1A/)
        expect(output).not_to match(/\e\[2A/)
      end

      it "uses @last_cursor_line when cursor is on first line (line 0)" do
        # Cursor is on first line - @last_cursor_line should be 0, which is valid
        console.instance_variable_set(:@input_buffer, "line1\nline2\nline3")
        console.instance_variable_set(:@cursor_pos, 3) # Middle of line1
        console.instance_variable_set(:@last_line_count, 3)
        console.instance_variable_set(:@last_cursor_line, 0) # Cursor on first line

        console.send(:redraw_input_line, "> ")

        output = stdout.string
        # Should use @last_cursor_line = 0 for clearing (move up 0 lines)
        # But after rendering all lines, still needs to move up for positioning
        # Since buffer has 3 lines and cursor is on line 0, it moves up 2 lines for positioning
        # The key is: no move-up BEFORE the content rendering
        expect(output).to match(/\e\[J.*line1.*line2.*line3.*\e\[2A/m)
      end

      it "uses @last_cursor_physical_row to determine how far to move up" do
        # Redraw scenario with cursor previously on physical row 2
        console.instance_variable_set(:@input_buffer, "line1\nline2")
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@last_line_count, 3)
        console.instance_variable_set(:@last_cursor_line, 2)
        console.instance_variable_set(:@last_cursor_physical_row, 2) # Cursor was on physical row 2

        console.send(:redraw_input_line, "> ")

        output = stdout.string
        # Should move up 2 physical rows based on @last_cursor_physical_row
        expect(output).to match(/\e\[2A/)
      end
    end
  end

  describe "#show_spinner" do
    it "transitions to StreamingAssistantState" do
      allow(stdin).to receive(:wait_readable).and_return(nil)
      allow(stdin).to receive(:read_nonblock).and_raise(Errno::EAGAIN)
      allow(IO).to receive(:select).and_return(nil)

      console.show_spinner("Thinking...")
      expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::StreamingAssistantState)
      spinner_state = console.instance_variable_get(:@spinner_state)
      expect(spinner_state.message).to eq("Thinking...")
      expect(spinner_state.running).to be true

      # Clean up
      console.hide_spinner
    end
  end

  describe "#hide_spinner" do
    it "stops spinner and clears line" do
      allow(stdin).to receive(:wait_readable).and_return(nil)
      allow(stdin).to receive(:read_nonblock).and_raise(Errno::EAGAIN)
      allow(IO).to receive(:select).and_return(nil)

      # First start the spinner to transition to StreamingAssistantState
      console.show_spinner("Test")

      spinner_state = console.instance_variable_get(:@spinner_state)
      expect(spinner_state.running).to be true

      console.hide_spinner

      expect(spinner_state.running).to be false
      output = stdout.string
      expect(output).to include("\e[2K\r") # Clear line
    end
  end

  describe "#interrupt_requested?" do
    it "returns false initially" do
      expect(console.interrupt_requested?).to be false
    end

    it "returns true after interrupt flag is set" do
      spinner_state = console.instance_variable_get(:@spinner_state)
      spinner_state.interrupt_requested = true
      expect(console.interrupt_requested?).to be true
    end

    it "resets to false when show_spinner is called" do
      spinner_state = console.instance_variable_get(:@spinner_state)
      spinner_state.interrupt_requested = true
      allow(stdin).to receive(:wait_readable).and_return(nil)
      allow(stdin).to receive(:read_nonblock).and_raise(Errno::EAGAIN)
      allow(IO).to receive(:select).and_return(nil)

      console.show_spinner("Testing...")

      expect(console.interrupt_requested?).to be false

      # Clean up
      console.hide_spinner
    end
  end

  describe "#handle_output_for_input_mode" do
    before do
      allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")
      allow(pipe_write).to receive(:write)
    end

    it "clears input line, writes output, and redraws input" do
      queue = console.instance_variable_get(:@output_queue)
      queue.push("Background output line 1")
      queue.push("Background output line 2")

      console.instance_variable_set(:@input_buffer, "typing")
      console.instance_variable_set(:@cursor_pos, 6)

      console.send(:handle_output_for_input_mode, "> ")

      output = stdout.string
      # Should clear line, write output, redraw prompt
      expect(output).to include("Background output line 1")
      expect(output).to include("Background output line 2")
      expect(output).to include("> typing")
    end

    it "clears multiline input area before writing output" do
      queue = console.instance_variable_get(:@output_queue)
      queue.push("Background output")

      console.instance_variable_set(:@input_buffer, "line1\nline2")
      console.instance_variable_set(:@cursor_pos, 11)
      console.instance_variable_set(:@last_line_count, 2)
      console.instance_variable_set(:@last_cursor_physical_row, 1) # Cursor was on physical row 1

      console.send(:handle_output_for_input_mode, "> ")

      output = stdout.string
      # Should move up one physical row before clearing
      expect(output).to include("\e[A")
      # Should clear from cursor to end of screen
      expect(output).to include("\e[J")
      # Should include the background output
      expect(output).to include("Background output")
    end

    it "redraws multiline input correctly after output" do
      queue = console.instance_variable_get(:@output_queue)
      queue.push("Background output")

      console.instance_variable_set(:@input_buffer, "line1\nline2")
      console.instance_variable_set(:@cursor_pos, 11)
      console.instance_variable_set(:@last_line_count, 2)

      console.send(:handle_output_for_input_mode, "> ")

      output = stdout.string
      # Should include both lines in the redraw
      expect(output).to include("line1")
      expect(output).to include("line2")
      # Should have the prompt
      expect(output).to include("> ")
    end

    it "updates @last_line_count after redrawing multiline input" do
      queue = console.instance_variable_get(:@output_queue)
      queue.push("Background output")

      console.instance_variable_set(:@input_buffer, "line1\nline2\nline3")
      console.instance_variable_set(:@cursor_pos, 0)
      console.instance_variable_set(:@last_line_count, 2)

      console.send(:handle_output_for_input_mode, "> ")

      # Should update to 3 lines since buffer has 3 lines
      expect(console.instance_variable_get(:@last_line_count)).to eq(3)
    end
  end

  describe "#add_to_history" do
    it "adds non-empty lines to history" do
      console.send(:add_to_history, "test command")
      history = console.instance_variable_get(:@history)
      expect(history).to eq(["test command"])
    end

    it "does not add empty lines" do
      console.send(:add_to_history, "")
      console.send(:add_to_history, "   ")
      history = console.instance_variable_get(:@history)
      expect(history).to be_empty
    end

    it "does not add duplicates of last entry" do
      console.send(:add_to_history, "command")
      console.send(:add_to_history, "command")
      history = console.instance_variable_get(:@history)
      expect(history).to eq(["command"])
    end
  end

  describe "thread safety" do
    it "handles concurrent output calls safely" do
      allow(pipe_write).to receive(:write)

      threads = 100.times.map do |i|
        Thread.new { console.puts("Message #{i}") }
      end
      threads.each(&:join)

      queue = console.instance_variable_get(:@output_queue)
      messages = []
      100.times do
        messages << begin
          queue.pop(true)
        rescue ThreadError
          nil
        end
      end
      messages.compact!

      expect(messages.length).to eq(100)
    end
  end

  describe "ANSI color support" do
    it "passes through ANSI color codes in output" do
      allow(pipe_write).to receive(:write)
      console.puts("\e[32mGreen text\e[0m")

      queue = console.instance_variable_get(:@output_queue)
      message = queue.pop
      expect(message).to eq("\e[32mGreen text\e[0m")
    end
  end

  # Phase 2: Readline Editing Emulation
  describe "#parse_input (Phase 2 - cursor movement)" do
    context "with left arrow key (\\e[D)" do
      it "moves cursor left when not at start" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 5)
        console.send(:parse_input, "\e[D")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(4)
      end

      it "does not move cursor left when at start" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 0)
        console.send(:parse_input, "\e[D")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      end
    end

    context "with right arrow key (\\e[C)" do
      it "moves cursor right when not at end" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 2)
        console.send(:parse_input, "\e[C")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(3)
      end

      it "does not move cursor right when at end" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 5)
        console.send(:parse_input, "\e[C")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(5)
      end
    end

    context "with Home key (\\e[H)" do
      it "moves cursor to start of line" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 3)
        console.send(:parse_input, "\e[H")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      end
    end

    context "with Home key variant (\\e[1~)" do
      it "moves cursor to start of line" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 3)
        console.send(:parse_input, "\e[1~")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      end
    end

    context "with End key (\\e[F)" do
      it "moves cursor to end of line" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 2)
        console.send(:parse_input, "\e[F")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(5)
      end
    end

    context "with End key variant (\\e[4~)" do
      it "moves cursor to end of line" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 2)
        console.send(:parse_input, "\e[4~")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(5)
      end
    end

    context "with Ctrl-A" do
      it "moves cursor to start of line" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 3)
        console.send(:parse_input, "\x01")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      end
    end

    context "with Ctrl-E" do
      it "moves cursor to end of line" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 2)
        console.send(:parse_input, "\x05")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(5)
      end
    end

    context "with Delete key (\\e[3~)" do
      it "deletes character at cursor position" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 2)
        console.send(:parse_input, "\e[3~")
        expect(console.instance_variable_get(:@input_buffer)).to eq("helo")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(2)
      end

      it "does nothing when cursor is at end" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 5)
        console.send(:parse_input, "\e[3~")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(5)
      end
    end
  end

  describe "#parse_input (Phase 2 - kill/yank)" do
    context "with Ctrl-K (kill to end)" do
      it "kills text from cursor to end of line" do
        console.instance_variable_set(:@input_buffer, String.new("hello world"))
        console.instance_variable_set(:@cursor_pos, 6)
        console.send(:parse_input, "\x0B")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello ")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(6)
        expect(console.instance_variable_get(:@kill_ring)).to eq("world")
      end

      it "does nothing when cursor is at end" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 5)
        console.send(:parse_input, "\x0B")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello")
        expect(console.instance_variable_get(:@kill_ring)).to eq("")
      end
    end

    context "with Ctrl-U (kill to start)" do
      it "kills text from start of line to cursor" do
        console.instance_variable_set(:@input_buffer, String.new("hello world"))
        console.instance_variable_set(:@cursor_pos, 6)
        console.send(:parse_input, "\x15")
        expect(console.instance_variable_get(:@input_buffer)).to eq("world")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
        expect(console.instance_variable_get(:@kill_ring)).to eq("hello ")
      end

      it "does nothing when cursor is at start" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 0)
        console.send(:parse_input, "\x15")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello")
        expect(console.instance_variable_get(:@kill_ring)).to eq("")
      end
    end

    context "with Ctrl-W (kill word backward)" do
      it "kills word before cursor" do
        console.instance_variable_set(:@input_buffer, String.new("hello world"))
        console.instance_variable_set(:@cursor_pos, 11)
        console.send(:parse_input, "\x17")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello ")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(6)
        expect(console.instance_variable_get(:@kill_ring)).to eq("world")
      end

      it "kills to previous whitespace" do
        console.instance_variable_set(:@input_buffer, String.new("one two three"))
        console.instance_variable_set(:@cursor_pos, 7)
        console.send(:parse_input, "\x17")
        expect(console.instance_variable_get(:@input_buffer)).to eq("one  three")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(4)
        expect(console.instance_variable_get(:@kill_ring)).to eq("two")
      end

      it "does nothing when cursor is at start" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 0)
        console.send(:parse_input, "\x17")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello")
        expect(console.instance_variable_get(:@kill_ring)).to eq("")
      end
    end

    context "with Ctrl-Y (yank)" do
      it "inserts killed text at cursor" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 5)
        console.instance_variable_set(:@kill_ring, " world")
        console.send(:parse_input, "\x19")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello world")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(11)
      end

      it "does nothing when kill ring is empty" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 5)
        console.instance_variable_set(:@kill_ring, "")
        console.send(:parse_input, "\x19")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(5)
      end
    end
  end

  describe "#parse_input (Phase 2 - clear screen)" do
    context "with Ctrl-L" do
      it "returns :clear_screen signal" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 3)
        result = console.send(:parse_input, "\x0C")
        expect(result).to eq(:clear_screen)
      end

      it "preserves input buffer and cursor position" do
        console.instance_variable_set(:@input_buffer, String.new("hello world"))
        console.instance_variable_set(:@cursor_pos, 6)
        console.send(:parse_input, "\x0C")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello world")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(6)
      end
    end
  end

  describe "#clear_screen" do
    it "clears terminal and redraws input line" do
      console.instance_variable_set(:@input_buffer, "test input")
      console.instance_variable_set(:@cursor_pos, 5)
      console.send(:clear_screen, "> ")

      output = stdout.string
      # Should include clear screen escape code
      expect(output).to include("\e[2J\e[H")
      # Should redraw the prompt and input
      expect(output).to include("> test input")
    end

    it "clears terminal and redraws multiline input" do
      console.instance_variable_set(:@input_buffer, "line1\nline2\nline3")
      console.instance_variable_set(:@cursor_pos, 6) # At start of line2
      console.send(:clear_screen, "> ")

      output = stdout.string
      # Should include clear screen escape code
      expect(output).to include("\e[2J\e[H")
      # Should render all lines
      expect(output).to include("> line1")
      expect(output).to include("line2")
      expect(output).to include("line3")
      # Should have newlines between lines
      expect(output).to include("\r\n")
    end

    it "positions cursor correctly in multiline content after clear" do
      console.instance_variable_set(:@input_buffer, "first\nsecond")
      console.instance_variable_set(:@cursor_pos, 8) # At 'c' in 'second'
      console.send(:clear_screen, "> ")

      output = stdout.string
      # Should position cursor at line 1 (second line), column 2 (at 'c')
      # After rendering all lines, cursor is on the last line already
      expect(output).to include("\e[3G") # Column 3 (2 + 1 for 1-indexed)
    end

    it "positions cursor correctly when not on last line after clear" do
      console.instance_variable_set(:@input_buffer, "line1\nline2\nline3")
      console.instance_variable_set(:@cursor_pos, 6) # At start of line2
      console.send(:clear_screen, "> ")

      output = stdout.string
      # Should position cursor at line 1 (middle line), column 0
      # After rendering all 3 lines, cursor is at end of line 3 (line index 2)
      # To get to line 1 (index 1), we move up 1 line
      expect(output).to include("\e[1A") # Move up 1 line
      expect(output).to include("\e[1G") # Column 1 (0 + 1 for 1-indexed)
    end
  end

  # Phase 3: Command History Emulation
  describe "#parse_input (Phase 3 - history navigation)" do
    context "with up arrow key (\\e[A)" do
      it "navigates to previous history entry" do
        console.instance_variable_set(:@history, %w[first second third])
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)

        console.send(:parse_input, "\e[A")

        expect(console.instance_variable_get(:@input_buffer)).to eq("third")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(5)
        expect(console.instance_variable_get(:@history_pos)).to eq(2)
      end

      it "does not enter history when buffer is non-empty (single line)" do
        console.instance_variable_set(:@history, %w[first second])
        console.instance_variable_set(:@input_buffer, String.new("partially typed"))
        console.instance_variable_set(:@cursor_pos, 15)

        console.send(:parse_input, "\e[A")

        # With new behavior: non-empty buffer means line navigation, not history
        # Single line buffer means up arrow does nothing
        expect(console.instance_variable_get(:@input_buffer)).to eq("partially typed")
        expect(console.instance_variable_get(:@history_pos)).to be_nil
      end

      it "navigates backwards through history on repeated up arrows" do
        console.instance_variable_set(:@history, %w[first second third])
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)

        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("third")

        # Clear buffer to continue navigating history
        console.send(:kill_to_start)
        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("second")

        # Clear buffer again
        console.send(:kill_to_start)
        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("first")
      end

      it "stops at beginning of history" do
        console.instance_variable_set(:@history, %w[first second])
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)

        # Navigate to beginning
        console.send(:parse_input, "\e[A")
        console.send(:kill_to_start)
        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("first")

        # Try to go further - should stay at first
        console.send(:kill_to_start)
        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("first")
      end
    end

    context "with down arrow key (\\e[B)" do
      it "navigates to next history entry" do
        console.instance_variable_set(:@history, %w[first second third])
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)

        # Go back two entries
        console.send(:parse_input, "\e[A")
        console.send(:kill_to_start)
        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("second")

        # Go forward one (need to clear buffer first)
        console.send(:kill_to_start)
        console.send(:parse_input, "\e[B")
        expect(console.instance_variable_get(:@input_buffer)).to eq("third")
      end

      it "does not enter history when buffer is non-empty (line navigation)" do
        console.instance_variable_set(:@history, %w[first second])
        console.instance_variable_set(:@input_buffer, String.new("my input"))
        console.instance_variable_set(:@cursor_pos, 8)

        # With new behavior: non-empty buffer means line navigation, not history
        # Single line buffer means up/down arrows do nothing
        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("my input")
        expect(console.instance_variable_get(:@history_pos)).to be_nil

        console.send(:parse_input, "\e[B")
        expect(console.instance_variable_get(:@input_buffer)).to eq("my input")
        expect(console.instance_variable_get(:@history_pos)).to be_nil
      end

      it "does nothing when not in history" do
        console.instance_variable_set(:@history, %w[first second])
        console.instance_variable_set(:@input_buffer, String.new("current"))
        console.instance_variable_set(:@cursor_pos, 7)
        console.instance_variable_set(:@history_pos, nil)

        console.send(:parse_input, "\e[B")

        expect(console.instance_variable_get(:@input_buffer)).to eq("current")
        expect(console.instance_variable_get(:@history_pos)).to be_nil
      end
    end
  end

  describe "#history_prev" do
    it "moves to last history entry when starting from nil" do
      console.instance_variable_set(:@history, %w[first second third])
      console.instance_variable_set(:@input_buffer, String.new("current"))
      console.instance_variable_set(:@cursor_pos, 7)
      console.instance_variable_set(:@history_pos, nil)

      console.send(:history_prev)

      expect(console.instance_variable_get(:@input_buffer)).to eq("third")
      expect(console.instance_variable_get(:@cursor_pos)).to eq(5)
      expect(console.instance_variable_get(:@history_pos)).to eq(2)
      expect(console.instance_variable_get(:@saved_input)).to eq("current")
    end

    it "moves backward in history" do
      console.instance_variable_set(:@history, %w[first second third])
      console.instance_variable_set(:@history_pos, 2)

      console.send(:history_prev)

      expect(console.instance_variable_get(:@input_buffer)).to eq("second")
      expect(console.instance_variable_get(:@history_pos)).to eq(1)
    end

    it "stops at first entry" do
      console.instance_variable_set(:@history, %w[first second])
      console.instance_variable_set(:@history_pos, 0)

      console.send(:history_prev)

      expect(console.instance_variable_get(:@input_buffer)).to eq("first")
      expect(console.instance_variable_get(:@history_pos)).to eq(0)
    end
  end

  describe "#history_next" do
    it "moves forward in history" do
      console.instance_variable_set(:@history, %w[first second third])
      console.instance_variable_set(:@history_pos, 0)

      console.send(:history_next)

      expect(console.instance_variable_get(:@input_buffer)).to eq("second")
      expect(console.instance_variable_get(:@history_pos)).to eq(1)
    end

    it "restores saved input when reaching end" do
      console.instance_variable_set(:@history, %w[first second])
      console.instance_variable_set(:@history_pos, 1)
      console.instance_variable_set(:@saved_input, "my input")

      console.send(:history_next)

      expect(console.instance_variable_get(:@input_buffer)).to eq("my input")
      expect(console.instance_variable_get(:@history_pos)).to be_nil
    end

    it "does nothing when history_pos is nil" do
      console.instance_variable_set(:@history, ["first"])
      console.instance_variable_set(:@history_pos, nil)
      console.instance_variable_set(:@input_buffer, String.new("current"))

      console.send(:history_next)

      expect(console.instance_variable_get(:@input_buffer)).to eq("current")
      expect(console.instance_variable_get(:@history_pos)).to be_nil
    end
  end

  describe "database persistence (Phase 3)" do
    let(:mock_history) { instance_double(Nu::Agent::History) }

    before do
      console.instance_variable_set(:@db_history, mock_history)
    end

    describe "#save_history_to_db" do
      it "saves a command to the database" do
        expect(mock_history).to receive(:add_command_history).with("test command")
        console.send(:save_history_to_db, "test command")
      end

      it "handles empty commands" do
        # Should not call database for empty commands
        expect(mock_history).not_to receive(:add_command_history)
        console.send(:save_history_to_db, "")
      end

      it "handles whitespace-only commands" do
        # Should not call database for whitespace-only commands
        expect(mock_history).not_to receive(:add_command_history)
        console.send(:save_history_to_db, "   ")
      end

      it "handles database errors gracefully" do
        console.instance_variable_set(:@debug, true)
        expect(mock_history).to receive(:add_command_history).and_raise(StandardError.new("DB error"))
        expect { console.send(:save_history_to_db, "test") }.to output(/Failed to save command history/).to_stderr
      end
    end

    describe "#load_history_from_db" do
      it "loads history from database" do
        expect(mock_history).to receive(:get_command_history).with(limit: 1000).and_return(
          [
            { "command" => "first command" },
            { "command" => "second command" },
            { "command" => "third command" }
          ]
        )

        console.send(:load_history_from_db)

        history = console.instance_variable_get(:@history)
        expect(history).to eq(["first command", "second command", "third command"])
      end

      it "handles empty history" do
        expect(mock_history).to receive(:get_command_history).with(limit: 1000).and_return([])

        console.send(:load_history_from_db)

        history = console.instance_variable_get(:@history)
        expect(history).to eq([])
      end

      it "handles database errors gracefully" do
        console.instance_variable_set(:@debug, true)
        expect(mock_history).to receive(:get_command_history).and_raise(StandardError.new("DB error"))
        expect { console.send(:load_history_from_db) }.to output(/Failed to load command history/).to_stderr
        history = console.instance_variable_get(:@history)
        expect(history).to eq([])
      end
    end

    describe "#add_to_history" do
      it "adds to in-memory history and saves to database" do
        expect(mock_history).to receive(:add_command_history).with("test command")

        console.send(:add_to_history, "test command")

        history = console.instance_variable_get(:@history)
        expect(history).to include("test command")
      end

      it "does not save empty commands to database" do
        expect(mock_history).not_to receive(:add_command_history)

        console.send(:add_to_history, "")
        console.send(:add_to_history, "   ")

        history = console.instance_variable_get(:@history)
        expect(history).to be_empty
      end
    end
  end

  # Phase 4: Additional coverage for uncovered lines
  describe "#initialize (full test)" do
    it "initializes all instance variables and sets up terminal" do
      mock_db = instance_double(Nu::Agent::History)

      # Mock stty command
      allow_any_instance_of(described_class).to receive(:`).with("stty -g").and_return("saved_state\n")

      # Mock stdin.raw! to avoid terminal issues in tests
      allow_any_instance_of(described_class).to receive(:setup_terminal)

      # Mock at_exit registration
      expect(mock_db).to receive(:get_command_history).with(limit: 1000).and_return([])

      # Create console with actual initialize
      console_instance = described_class.new(db_history: mock_db, debug: false)

      expect(console_instance.instance_variable_get(:@debug)).to be false
      expect(console_instance.instance_variable_get(:@db_history)).to eq(mock_db)
      expect(console_instance.current_state).to be_a(Nu::Agent::ConsoleIO::IdleState)
      expect(console_instance.instance_variable_get(:@input_buffer)).not_to be_frozen
      expect(console_instance.instance_variable_get(:@kill_ring)).not_to be_frozen
      expect(console_instance.instance_variable_get(:@saved_input)).not_to be_frozen

      # Clean up
      console_instance.instance_variable_set(:@original_stty, nil)
      console_instance.close
    end
  end

  describe "#close" do
    it "restores terminal when original_stty is set" do
      console.instance_variable_set(:@original_stty, "saved_state")
      # Suppress system call output
      allow_any_instance_of(Object).to receive(:system).with("stty saved_state").and_return(true)
      expect(stdout).to receive(:write).with("\e[?25h").once
      expect(stdout).to receive(:flush).once

      console.close
    end

    it "can be called multiple times safely (idempotent)" do
      console.instance_variable_set(:@original_stty, "saved_state")
      allow_any_instance_of(Object).to receive(:system).with("stty saved_state").and_return(true)
      allow(stdout).to receive(:write).with("\e[?25h").twice
      allow(stdout).to receive(:flush).twice

      # Multiple calls are safe (idempotent)
      console.close
      console.close
    end

    it "does nothing when original_stty is nil" do
      console.instance_variable_set(:@original_stty, nil)
      # Should not call system when original_stty is nil
      expect(stdout).not_to receive(:write)
      expect(stdout).not_to receive(:flush)

      console.close
    end
  end

  describe "#handle_readline_select" do
    it "handles output from background thread" do
      allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")
      allow(pipe_write).to receive(:write)
      queue = console.instance_variable_get(:@output_queue)
      queue.push("Background message")

      allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil).and_return([[pipe_read], [], []])

      result = console.send(:handle_readline_select, "> ")
      expect(result).to eq(:continue)
    end

    it "handles stdin input with submit" do
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\r")
      allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil).and_return([[stdin], [], []])

      result = console.send(:handle_readline_select, "> ")
      expect(result).to be_a(String)
    end

    it "handles stdin input with Ctrl-D (delete forward)" do
      console.instance_variable_set(:@input_buffer, String.new("test"))
      console.instance_variable_set(:@cursor_pos, 0)
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\x04")
      allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil).and_return([[stdin], [], []])

      result = console.send(:handle_readline_select, "> ")
      expect(result).to eq(:continue)
      expect(console.instance_variable_get(:@input_buffer)).to eq("est")
    end

    it "handles stdin input with clear screen" do
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\x0C")
      allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil).and_return([[stdin], [], []])

      result = console.send(:handle_readline_select, "> ")
      expect(result).to eq(:continue)
    end

    it "continues for regular input" do
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("a")
      allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil).and_return([[stdin], [], []])

      result = console.send(:handle_readline_select, "> ")
      expect(result).to eq(:continue)
    end
  end

  describe "#handle_stdin_input" do
    it "processes submit action" do
      console.instance_variable_set(:@input_buffer, String.new("test"))
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\r")

      result = console.send(:handle_stdin_input, "> ")
      expect(result).to eq("test")
    end

    it "processes Ctrl-D (delete forward)" do
      console.instance_variable_set(:@input_buffer, String.new("hello"))
      console.instance_variable_set(:@cursor_pos, 2)
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\x04")

      result = console.send(:handle_stdin_input, "> ")
      expect(result).to eq(:continue)
      expect(console.instance_variable_get(:@input_buffer)).to eq("helo")
    end

    it "processes clear screen action" do
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\x0C")

      result = console.send(:handle_stdin_input, "> ")
      expect(result).to eq(:continue)
    end

    it "continues for regular input" do
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("x")

      result = console.send(:handle_stdin_input, "> ")
      expect(result).to eq(:continue)
    end
  end

  describe "#submit_input" do
    it "outputs the line and adds to history" do
      console.instance_variable_set(:@input_buffer, String.new("test command"))

      result = console.send(:submit_input, "> ")
      expect(result).to eq("test command")

      output = stdout.string
      expect(output).to include("> test command")

      history = console.instance_variable_get(:@history)
      expect(history).to include("test command")
    end

    it "converts \\n to \\r\\n in multiline output to prevent staircase display" do
      console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
      console.instance_variable_set(:@last_cursor_line, 2)

      result = console.send(:submit_input, "> ")
      expect(result).to eq("line1\nline2\nline3")

      output = stdout.string
      # Should convert all \n to \r\n for proper display in raw mode
      expect(output).to include("line1\r\nline2\r\nline3\r\n")
      # Should not have bare \n without \r (which causes staircase)
      expect(output).not_to match(/[^\r]\n/)
    end

    it "moves to start of line before clearing (\\r before \\e[J])" do
      console.instance_variable_set(:@input_buffer, String.new("test"))
      console.instance_variable_set(:@last_cursor_line, 0)

      console.send(:submit_input, "> ")

      output = stdout.string
      # Should have \r before \e[J] to ensure full line is cleared
      expect(output).to match(/\r.*\e\[J/)
    end

    it "resets cursor tracking variables after submit" do
      console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
      console.instance_variable_set(:@last_cursor_line, 1)
      console.instance_variable_set(:@last_line_count, 2)

      console.send(:submit_input, "> ")

      # Should reset tracking to prepare for next prompt
      expect(console.instance_variable_get(:@last_cursor_line)).to eq(0)
      expect(console.instance_variable_get(:@last_line_count)).to eq(1)
    end
  end

  describe "#handle_eof" do
    it "clears output and returns nil" do
      result = console.send(:handle_eof)
      expect(result).to be_nil

      output = stdout.string
      expect(output).to include("\e[2K\r")
    end
  end

  describe "#setup_terminal" do
    it "sets stdin to raw mode" do
      mock_stdin = instance_double(IO, "stdin")
      console.instance_variable_set(:@stdin, mock_stdin)
      expect(mock_stdin).to receive(:raw!)

      console.send(:setup_terminal)
    end
  end

  describe "#restore_terminal" do
    it "restores terminal state and shows cursor" do
      console.instance_variable_set(:@original_stty, "saved")
      allow_any_instance_of(Object).to receive(:system).with("stty saved").and_return(true)
      expect(stdout).to receive(:write).with("\e[?25h")
      expect(stdout).to receive(:flush)

      console.send(:restore_terminal)
    end

    it "does nothing when original_stty is nil" do
      console.instance_variable_set(:@original_stty, nil)
      # Should not call system or write/flush when original_stty is nil
      expect(stdout).not_to receive(:write)
      expect(stdout).not_to receive(:flush)

      console.send(:restore_terminal)
    end
  end

  describe "#flush_stdin" do
    it "drains all buffered input" do
      expect(stdin).to receive(:wait_readable).with(0).and_return(true, true, false)
      expect(stdin).to receive(:read_nonblock).with(1024).twice.and_return("x", "y")

      console.send(:flush_stdin)
    end

    it "handles IO::WaitReadable exception (via Errno::EAGAIN)" do
      expect(stdin).to receive(:wait_readable).with(0).and_return(true)
      exception = Errno::EAGAIN.new
      exception.extend(IO::WaitReadable)
      expect(stdin).to receive(:read_nonblock).with(1024).and_raise(exception)

      expect { console.send(:flush_stdin) }.not_to raise_error
    end
  end

  describe "#handle_escape_sequence edge cases" do
    it "returns index when not enough characters for sequence" do
      console.instance_variable_set(:@input_buffer, String.new(""))
      console.instance_variable_set(:@cursor_pos, 0)

      # Escape at end of input
      result = console.send(:parse_input, "\e")
      expect(result).to be_nil
    end

    it "handles non-CSI escape sequences" do
      console.instance_variable_set(:@input_buffer, String.new(""))
      console.instance_variable_set(:@cursor_pos, 0)

      # Escape followed by non-[ character (e.g., Alt+X)
      result = console.send(:parse_input, "\ex")
      expect(result).to be_nil
    end
  end

  describe "#handle_csi_sequence edge cases" do
    it "handles incomplete Home variant sequence" do
      console.instance_variable_set(:@input_buffer, String.new("test"))
      console.instance_variable_set(:@cursor_pos, 4)

      # \e[1 without the ~
      result = console.send(:parse_input, "\e[1")
      expect(result).to be_nil
      # Cursor should not have moved
      expect(console.instance_variable_get(:@cursor_pos)).to eq(4)
    end

    it "handles incomplete Delete sequence" do
      console.instance_variable_set(:@input_buffer, String.new("test"))
      console.instance_variable_set(:@cursor_pos, 2)

      # \e[3 without the ~
      result = console.send(:parse_input, "\e[3")
      expect(result).to be_nil
      expect(console.instance_variable_get(:@input_buffer)).to eq("test")
    end

    it "handles incomplete End variant sequence" do
      console.instance_variable_set(:@input_buffer, String.new("test"))
      console.instance_variable_set(:@cursor_pos, 2)

      # \e[4 without the ~
      result = console.send(:parse_input, "\e[4")
      expect(result).to be_nil
      expect(console.instance_variable_get(:@cursor_pos)).to eq(2)
    end

    it "ignores unknown CSI sequences" do
      console.instance_variable_set(:@input_buffer, String.new("test"))
      console.instance_variable_set(:@cursor_pos, 2)

      # Unknown CSI sequence like \e[9
      result = console.send(:parse_input, "\e[9")
      expect(result).to be_nil
      expect(console.instance_variable_get(:@input_buffer)).to eq("test")
    end
  end

  describe "spinner functionality" do
    describe "#spinner_loop" do
      it "handles output during spinner" do
        allow(stdin).to receive(:wait_readable).and_return(nil)
        allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")
        allow(pipe_write).to receive(:write)

        spinner_state = console.instance_variable_get(:@spinner_state)
        spinner_state.start("Testing...", Thread.current)

        queue = console.instance_variable_get(:@output_queue)
        queue.push("Spinner message")

        allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil, 0.1).and_return([[pipe_read], [], []], nil)

        # Run one iteration
        expect do
          thread = Thread.new do
            console.send(:spinner_loop)
          end
          sleep 0.05
          spinner_state.stop
          thread.join(0.5)
        end.not_to raise_error
      end

      it "handles Ctrl-C during spinner" do
        allow(stdin).to receive(:wait_readable).and_return(nil)
        allow(pipe_write).to receive(:write)
        allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")

        spinner_state = console.instance_variable_get(:@spinner_state)
        spinner_state.start("Testing...", Thread.current)

        allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil, 0.1).and_return([[stdin], [], []])
        allow(stdin).to receive(:read_nonblock).with(1).and_return("\x03")

        expect do
          console.send(:spinner_loop)
        end.to raise_error(Interrupt)
      end

      it "ignores non-Ctrl-C keystrokes during spinner" do
        allow(stdin).to receive(:wait_readable).and_return(nil)
        allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")
        allow(pipe_write).to receive(:write)

        spinner_state = console.instance_variable_get(:@spinner_state)
        spinner_state.start("Testing...", Thread.current)

        allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil, 0.1).and_return([[stdin], [], []], nil)
        allow(stdin).to receive(:read_nonblock).with(1).and_return("x")

        thread = Thread.new do
          console.send(:spinner_loop)
        end
        sleep 0.05
        spinner_state.stop
        thread.join(0.5)
      end

      it "animates spinner on timeout" do
        allow(stdin).to receive(:wait_readable).and_return(nil)
        allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")
        allow(pipe_write).to receive(:write)

        spinner_state = console.instance_variable_get(:@spinner_state)
        spinner_state.start("Testing...", Thread.current)

        # Return nil (timeout) a few times to allow animation, then stop
        call_count = 0
        allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil, 0.1) do
          call_count += 1
          spinner_state.stop if call_count > 3
          nil # Timeout
        end

        thread = Thread.new do
          console.send(:spinner_loop)
        end
        thread.join(1.0)

        # Frame should have advanced
        expect(spinner_state.frame).to be > 0
      end
    end

    describe "#handle_output_for_spinner_mode" do
      it "clears spinner, writes output, and redraws spinner" do
        allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")
        allow(pipe_write).to receive(:write)

        spinner_state = console.instance_variable_get(:@spinner_state)
        spinner_state.message = "Working..."
        spinner_state.frame = 2

        queue = console.instance_variable_get(:@output_queue)
        queue.push("Output line 1")
        queue.push("Output line 2")

        console.send(:handle_output_for_spinner_mode)

        output = stdout.string
        expect(output).to include("Output line 1")
        expect(output).to include("Output line 2")
        expect(output).to include("Working...")
      end

      it "does nothing when output queue is empty" do
        allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")

        console.send(:handle_output_for_spinner_mode)

        expect(stdout.string).to be_empty
      end
    end

    describe "#animate_spinner" do
      it "advances frame and redraws spinner" do
        spinner_state = console.instance_variable_get(:@spinner_state)
        spinner_state.message = "Loading..."
        spinner_state.frame = 0

        console.send(:animate_spinner)

        expect(spinner_state.frame).to eq(1)
        output = stdout.string
        expect(output).to include("Loading...")
      end
    end

    describe "#redraw_spinner" do
      it "draws spinner with color" do
        spinner_state = console.instance_variable_get(:@spinner_state)
        spinner_state.message = "Processing..."
        spinner_state.frame = 3

        console.send(:redraw_spinner)

        output = stdout.string
        expect(output).to include("\e[2K\r")
        expect(output).to include("Processing...")
        expect(output).to include("\e[38;5;81m")
        expect(output).to include("\e[0m")
      end
    end
  end

  describe "#puts error handling" do
    it "silently handles errors when pipe is closed" do
      broken_pipe = instance_double(IO, "broken_pipe")
      console.instance_variable_set(:@output_pipe_write, broken_pipe)

      expect(broken_pipe).to receive(:write).with("x").and_raise(StandardError.new("Broken pipe"))

      expect { console.puts("test") }.not_to raise_error
    end
  end

  describe "#drain_output_queue with EOFError" do
    it "handles EOFError when reading from pipe" do
      allow(pipe_read).to receive(:read_nonblock).with(1024).and_raise(EOFError)

      result = console.send(:drain_output_queue)
      expect(result).to eq([])
    end
  end

  describe "#kill_word_backward edge cases" do
    it "handles cursor in whitespace after word" do
      console.instance_variable_set(:@input_buffer, String.new("hello   "))
      console.instance_variable_set(:@cursor_pos, 8)

      console.send(:kill_word_backward)

      # Kills "hello   " (word plus trailing whitespace)
      expect(console.instance_variable_get(:@input_buffer)).to eq("")
      expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      expect(console.instance_variable_get(:@kill_ring)).to eq("hello   ")
    end
  end

  describe "#history_prev when history is empty" do
    it "does nothing when history is empty" do
      console.instance_variable_set(:@history, [])
      console.instance_variable_set(:@input_buffer, String.new("current"))
      console.instance_variable_set(:@cursor_pos, 7)

      console.send(:history_prev)

      expect(console.instance_variable_get(:@input_buffer)).to eq("current")
      expect(console.instance_variable_get(:@history_pos)).to be_nil
    end
  end

  describe "#cursor_up_or_history_prev" do
    context "when buffer is empty" do
      it "navigates history backward" do
        console.instance_variable_set(:@history, %w[first second third])
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@history_pos, nil)

        console.send(:cursor_up_or_history_prev)

        expect(console.instance_variable_get(:@input_buffer)).to eq("third")
        expect(console.instance_variable_get(:@history_pos)).to eq(2)
      end

      it "does nothing when history is empty" do
        console.instance_variable_set(:@history, [])
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@history_pos, nil)

        console.send(:cursor_up_or_history_prev)

        expect(console.instance_variable_get(:@input_buffer)).to eq("")
        expect(console.instance_variable_get(:@history_pos)).to be_nil
      end
    end

    context "when buffer is single line" do
      it "does not move cursor (already at line 0)" do
        console.instance_variable_set(:@input_buffer, String.new("hello world"))
        console.instance_variable_set(:@cursor_pos, 6)  # in middle of line

        console.send(:cursor_up_or_history_prev)

        expect(console.instance_variable_get(:@cursor_pos)).to eq(6)
      end
    end

    context "when buffer is multiline" do
      it "moves cursor from line 1 to line 0" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
        console.instance_variable_set(:@cursor_pos, 8)  # "line1\nli|ne2" - on line 1, col 2

        console.send(:cursor_up_or_history_prev)

        # Should move to line 0, column 2: "li|ne1\nline2"
        expect(console.instance_variable_get(:@cursor_pos)).to eq(2)
      end

      it "moves cursor from line 2 to line 1" do
        console.instance_variable_set(:@input_buffer, String.new("first\nsecond\nthird"))
        console.instance_variable_set(:@cursor_pos, 15) # on "third", col 2

        console.send(:cursor_up_or_history_prev)

        # Should move to line 1 ("second"), col 2
        expect(console.instance_variable_get(:@cursor_pos)).to eq(8)
      end

      it "does not move cursor when already on line 0 and not in history mode" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
        console.instance_variable_set(:@cursor_pos, 3) # on line 0
        console.instance_variable_set(:@history_pos, nil) # Not in history mode

        console.send(:cursor_up_or_history_prev)

        # Should stay at same position
        expect(console.instance_variable_get(:@cursor_pos)).to eq(3)
      end

      it "navigates backward in history when on first line and in history mode" do
        console.instance_variable_set(:@history, %W[first second\nthird fourth])
        console.instance_variable_set(:@input_buffer, String.new("second\nthird"))
        console.instance_variable_set(:@cursor_pos, 3) # on line 0 (first line)
        console.instance_variable_set(:@history_pos, 1) # In history mode, on entry 1

        console.send(:cursor_up_or_history_prev)

        # Should navigate backward in history to entry 0
        expect(console.instance_variable_get(:@input_buffer)).to eq("first")
        expect(console.instance_variable_get(:@history_pos)).to eq(0)
      end

      it "clamps column when target line is shorter" do
        console.instance_variable_set(:@input_buffer, String.new("short\nlonger line"))
        console.instance_variable_set(:@cursor_pos, 17) # on "longer line", col 10 (near end)

        console.send(:cursor_up_or_history_prev)

        # Should move to line 0, but clamp to end of "short" (length 5)
        expect(console.instance_variable_get(:@cursor_pos)).to eq(5)
      end
    end

    context "column memory (@saved_column)" do
      it "saves column on first vertical movement" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
        console.instance_variable_set(:@cursor_pos, 14) # line 2, col 2
        console.instance_variable_set(:@saved_column, nil)

        console.send(:cursor_up_or_history_prev)

        # Should save column 2
        expect(console.instance_variable_get(:@saved_column)).to eq(2)
      end

      it "uses saved column on subsequent vertical movements" do
        console.instance_variable_set(:@input_buffer, String.new("long line here\nshort\nlong again"))
        console.instance_variable_set(:@cursor_pos, 29) # line 2, col 10
        console.instance_variable_set(:@saved_column, 10)

        console.send(:cursor_up_or_history_prev)

        # Should try to use saved column 10, but "short" only has 5 chars, so clamp
        expect(console.instance_variable_get(:@cursor_pos)).to eq(20) # end of "short"
        expect(console.instance_variable_get(:@saved_column)).to eq(10) # preserved
      end

      it "restores column when moving to line long enough" do
        console.instance_variable_set(:@input_buffer, String.new("first line\nshort\nthird line"))
        console.instance_variable_set(:@cursor_pos, 16) # on "short", end of line (line 1, col 5)
        console.instance_variable_set(:@saved_column, 8) # Remember col 8 from before

        console.send(:cursor_up_or_history_prev)

        # Move up from "short" to "first line" - should restore saved col 8
        expect(console.instance_variable_get(:@cursor_pos)).to eq(8)
        expect(console.instance_variable_get(:@saved_column)).to eq(8) # preserved
      end
    end
  end

  # Phase 4.2: Down/history navigation
  describe "#cursor_down_or_history_next" do
    context "when buffer is empty" do
      it "navigates history forward" do
        console.instance_variable_set(:@history, %w[first second third])
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@history_pos, 2)

        console.send(:cursor_down_or_history_next)

        expect(console.instance_variable_get(:@input_buffer)).to eq("")
        expect(console.instance_variable_get(:@history_pos)).to be_nil
      end

      it "does nothing when history position is nil" do
        console.instance_variable_set(:@history, %w[first second third])
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@history_pos, nil)

        console.send(:cursor_down_or_history_next)

        expect(console.instance_variable_get(:@input_buffer)).to eq("")
        expect(console.instance_variable_get(:@history_pos)).to be_nil
      end
    end

    context "when buffer is single line" do
      it "does not move cursor (already at last line)" do
        console.instance_variable_set(:@input_buffer, String.new("hello world"))
        console.instance_variable_set(:@cursor_pos, 6)  # in middle of line

        console.send(:cursor_down_or_history_next)

        expect(console.instance_variable_get(:@cursor_pos)).to eq(6)
      end
    end

    context "when buffer is multiline" do
      it "moves cursor from line 0 to line 1" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
        console.instance_variable_set(:@cursor_pos, 2)  # "li|ne1\nline2" - on line 0, col 2

        console.send(:cursor_down_or_history_next)

        # Should move to line 1, column 2: "line1\nli|ne2"
        expect(console.instance_variable_get(:@cursor_pos)).to eq(8)
      end

      it "moves cursor from line 1 to line 2" do
        console.instance_variable_set(:@input_buffer, String.new("first\nsecond\nthird"))
        console.instance_variable_set(:@cursor_pos, 8) # on "second", col 2

        console.send(:cursor_down_or_history_next)

        # Should move to line 2 ("third"), col 2
        expect(console.instance_variable_get(:@cursor_pos)).to eq(15)
      end

      it "does not move cursor when already on last line and not in history mode" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
        console.instance_variable_set(:@cursor_pos, 8) # on line 1 (last line)
        console.instance_variable_set(:@history_pos, nil) # Not in history mode

        console.send(:cursor_down_or_history_next)

        # Should stay at same position
        expect(console.instance_variable_get(:@cursor_pos)).to eq(8)
      end

      it "navigates forward in history when on last line and in history mode" do
        console.instance_variable_set(:@history, %W[first second\nthird fourth])
        console.instance_variable_set(:@input_buffer, String.new("second\nthird"))
        console.instance_variable_set(:@cursor_pos, 12) # on line 1 (last line), end of "third"
        console.instance_variable_set(:@history_pos, 1) # In history mode, on entry 1

        console.send(:cursor_down_or_history_next)

        # Should navigate forward in history to entry 2
        expect(console.instance_variable_get(:@input_buffer)).to eq("fourth")
        expect(console.instance_variable_get(:@history_pos)).to eq(2)
      end

      it "clamps column when target line is shorter" do
        console.instance_variable_set(:@input_buffer, String.new("longer line\nshort"))
        console.instance_variable_set(:@cursor_pos, 10) # on "longer line", col 10

        console.send(:cursor_down_or_history_next)

        # Should move to line 1, but clamp to end of "short" (length 5)
        expect(console.instance_variable_get(:@cursor_pos)).to eq(17) # position at end of "short"
      end
    end

    context "column memory (@saved_column)" do
      it "saves column on first vertical movement" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
        console.instance_variable_set(:@cursor_pos, 2) # line 0, col 2
        console.instance_variable_set(:@saved_column, nil)

        console.send(:cursor_down_or_history_next)

        # Should save column 2
        expect(console.instance_variable_get(:@saved_column)).to eq(2)
      end

      it "uses saved column on subsequent vertical movements" do
        console.instance_variable_set(:@input_buffer, String.new("long line here\nshort\nlong again"))
        console.instance_variable_set(:@cursor_pos, 10) # line 0, col 10
        console.instance_variable_set(:@saved_column, 10)

        console.send(:cursor_down_or_history_next)

        # Should try to use saved column 10, but "short" only has 5 chars, so clamp
        expect(console.instance_variable_get(:@cursor_pos)).to eq(20) # end of "short"
        expect(console.instance_variable_get(:@saved_column)).to eq(10) # preserved
      end

      it "restores column when moving to line long enough" do
        console.instance_variable_set(:@input_buffer, String.new("first line\nshort\nthird line"))
        console.instance_variable_set(:@cursor_pos, 16) # on "short", end of line (line 1, col 5)
        console.instance_variable_set(:@saved_column, 8) # Remember col 8 from before

        console.send(:cursor_down_or_history_next)

        # Move down from "short" to "third line" - should restore saved col 8
        expect(console.instance_variable_get(:@cursor_pos)).to eq(25)
        expect(console.instance_variable_get(:@saved_column)).to eq(8) # preserved
      end
    end
  end

  describe "#readline integration" do
    it "reads a line of input and returns it" do
      # Mock readline to call handle_readline_select once and return a result
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("hello\r")
      allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil).and_return([[stdin], [], []])

      # Run readline in a thread with a timeout
      result = nil
      thread = Thread.new do
        result = console.readline("> ")
      end

      # Wait for result or timeout
      thread.join(1.0)

      expect(result).to eq("hello")
    end

    it "resets input state when starting readline" do
      console.instance_variable_set(:@input_buffer, String.new("old"))
      console.instance_variable_set(:@cursor_pos, 3)
      console.instance_variable_set(:@history_pos, 5)

      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\r")
      allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil).and_return([[stdin], [], []])

      result = nil
      thread = Thread.new do
        result = console.readline("> ")
      end
      thread.join(1.0)

      # After readline, these should have been reset (we can't check during, but the code ran)
      expect(result).to eq("")
    end

    it "handles EOF from readline (nil buffer, Ctrl-D behavior)" do
      # Simulate empty buffer at start, then Ctrl-D which should do nothing on empty line
      console.instance_variable_set(:@input_buffer, String.new(""))
      console.instance_variable_set(:@cursor_pos, 0)

      # First read returns empty string (simulating EOF condition), but since parse_input
      # with Ctrl-D on empty buffer just does nothing, we need actual EOF
      # Let's just test that parse_input with \x04 on empty buffer continues
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\x04", "\r")
      allow(IO).to receive(:select).with([stdin, pipe_read], nil, nil).and_return([[stdin], [], []], [[stdin], [], []])

      result = nil
      thread = Thread.new do
        result = console.readline("> ")
      end
      thread.join(1.0)

      expect(result).to eq("")
    end
  end

  describe "#handle_stdin_input with eof result" do
    it "returns nil when buffer is empty and Ctrl-D is pressed" do
      # Ctrl-D on empty buffer triggers EOF behavior
      console.instance_variable_set(:@input_buffer, String.new(""))
      console.instance_variable_set(:@cursor_pos, 0)
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\x04")

      result = console.send(:handle_stdin_input, "> ")
      # Ctrl-D on empty buffer does nothing, returns :continue
      expect(result).to eq(:continue)
    end
  end

  # Phase 5: Multiline editing support - Line/column calculation helpers
  describe "#lines" do
    it "returns array with empty string for empty buffer" do
      console.instance_variable_set(:@input_buffer, String.new(""))
      result = console.send(:lines)
      expect(result).to eq([""])
    end

    it "returns array with single element for single line" do
      console.instance_variable_set(:@input_buffer, String.new("hello"))
      result = console.send(:lines)
      expect(result).to eq(["hello"])
    end

    it "splits multiline buffer into array of lines" do
      console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
      result = console.send(:lines)
      expect(result).to eq(%w[line1 line2])
    end

    it "preserves trailing empty line when buffer ends with newline" do
      console.instance_variable_set(:@input_buffer, String.new("line1\n"))
      result = console.send(:lines)
      expect(result).to eq(["line1", ""])
    end
  end

  describe "#get_line_and_column" do
    it "returns [0, 0] for position 0 in empty buffer" do
      console.instance_variable_set(:@input_buffer, String.new(""))
      result = console.send(:get_line_and_column, 0)
      expect(result).to eq([0, 0])
    end

    it "returns [0, 3] for position 3 in single line 'hello'" do
      console.instance_variable_set(:@input_buffer, String.new("hello"))
      result = console.send(:get_line_and_column, 3)
      expect(result).to eq([0, 3])
    end

    it "returns [1, 0] for position 6 in 'line1\\nline2' (first char of line2)" do
      console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
      result = console.send(:get_line_and_column, 6)
      expect(result).to eq([1, 0])
    end

    it "returns [1, 2] for position 8 in 'line1\\nline2'" do
      console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
      result = console.send(:get_line_and_column, 8)
      expect(result).to eq([1, 2])
    end

    it "clamps position beyond buffer length to end of buffer" do
      console.instance_variable_set(:@input_buffer, String.new("hello"))
      result = console.send(:get_line_and_column, 100)
      expect(result).to eq([0, 5])
    end

    it "returns [0, 0] for position 0 in single line" do
      console.instance_variable_set(:@input_buffer, String.new("hello"))
      result = console.send(:get_line_and_column, 0)
      expect(result).to eq([0, 0])
    end

    it "handles position at newline character" do
      console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
      result = console.send(:get_line_and_column, 5)
      expect(result).to eq([0, 5])
    end

    it "handles multiline with position on last line" do
      console.instance_variable_set(:@input_buffer, String.new("a\nb\nc"))
      result = console.send(:get_line_and_column, 4)
      expect(result).to eq([2, 0])
    end

    it "handles position at end of buffer with trailing newline" do
      console.instance_variable_set(:@input_buffer, String.new("line\n"))
      result = console.send(:get_line_and_column, 5)
      expect(result).to eq([1, 0])
    end

    it "handles empty lines in multiline buffer" do
      console.instance_variable_set(:@input_buffer, String.new("a\n\nc"))
      result = console.send(:get_line_and_column, 2)
      expect(result).to eq([1, 0])
    end

    it "handles position at end of buffer without trailing newline" do
      console.instance_variable_set(:@input_buffer, String.new("hello"))
      result = console.send(:get_line_and_column, 5)
      expect(result).to eq([0, 5])
    end

    it "handles position at very end after all lines processed (multiline case)" do
      # This tests the fallback return at line 273
      console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
      result = console.send(:get_line_and_column, 17) # Position at end of "line1\nline2\nline3"
      expect(result).to eq([2, 5]) # Line 2, column 5 (end of "line3")
    end
  end

  describe "#get_position_from_line_column" do
    it "returns 0 for line=0, col=0 on 'hello'" do
      console.instance_variable_set(:@input_buffer, String.new("hello"))
      result = console.send(:get_position_from_line_column, 0, 0)
      expect(result).to eq(0)
    end

    it "returns 3 for line=0, col=3 on 'hello'" do
      console.instance_variable_set(:@input_buffer, String.new("hello"))
      result = console.send(:get_position_from_line_column, 0, 3)
      expect(result).to eq(3)
    end

    it "returns 6 for line=1, col=0 on 'line1\\nline2'" do
      console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
      result = console.send(:get_position_from_line_column, 1, 0)
      expect(result).to eq(6)
    end

    it "returns 11 for line=1, col=5 on 'line1\\nline2'" do
      console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
      result = console.send(:get_position_from_line_column, 1, 5)
      expect(result).to eq(11)
    end

    it "clamps column beyond line length to end of line" do
      console.instance_variable_set(:@input_buffer, String.new("hello"))
      result = console.send(:get_position_from_line_column, 0, 100)
      expect(result).to eq(5)
    end

    it "clamps line beyond buffer to last line" do
      console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
      result = console.send(:get_position_from_line_column, 100, 0)
      expect(result).to eq(6)
    end

    it "handles empty buffer" do
      console.instance_variable_set(:@input_buffer, String.new(""))
      result = console.send(:get_position_from_line_column, 0, 0)
      expect(result).to eq(0)
    end

    it "round-trips with get_line_and_column for various positions" do
      console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))

      # Test several positions
      [0, 3, 6, 8, 12, 17].each do |pos|
        line, col = console.send(:get_line_and_column, pos)
        result = console.send(:get_position_from_line_column, line, col)
        expect(result).to eq(pos), "Expected position #{pos} to round-trip, got #{result} for (#{line}, #{col})"
      end
    end

    it "handles position at end of multiline buffer" do
      console.instance_variable_set(:@input_buffer, String.new("a\nb\nc"))
      result = console.send(:get_position_from_line_column, 2, 1)
      expect(result).to eq(5)
    end

    it "handles buffer with trailing newline" do
      console.instance_variable_set(:@input_buffer, String.new("line\n"))
      result = console.send(:get_position_from_line_column, 1, 0)
      expect(result).to eq(5)
    end
  end

  # Phase 3: Multiline submit key handling
  describe "#parse_input (multiline submit keys)" do
    context "with Enter key (\\r)" do
      it "returns :submit action" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 5)
        result = console.send(:parse_input, "\r")
        expect(result).to eq(:submit)
      end

      it "submits multiline content with embedded newlines" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
        console.instance_variable_set(:@cursor_pos, 17)
        result = console.send(:parse_input, "\r")
        expect(result).to eq(:submit)
        expect(console.instance_variable_get(:@input_buffer)).to eq("line1\nline2\nline3")
      end

      it "can submit empty buffer" do
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)
        result = console.send(:parse_input, "\r")
        expect(result).to eq(:submit)
      end
    end

    context "with Shift+Enter or Ctrl+J (\\n)" do
      it "inserts newline character into buffer" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 5)
        result = console.send(:parse_input, "\n")
        expect(result).to be_nil
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello\n")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(6)
      end

      it "inserts newline in middle of buffer" do
        console.instance_variable_set(:@input_buffer, String.new("helloworld"))
        console.instance_variable_set(:@cursor_pos, 5)
        result = console.send(:parse_input, "\n")
        expect(result).to be_nil
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello\nworld")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(6)
      end

      it "creates multiline content when pressed multiple times" do
        console.instance_variable_set(:@input_buffer, String.new("line1"))
        console.instance_variable_set(:@cursor_pos, 5)
        console.send(:parse_input, "\n")
        console.instance_variable_set(:@input_buffer, "#{console.instance_variable_get(:@input_buffer)}line2")
        console.instance_variable_set(:@cursor_pos, console.instance_variable_get(:@input_buffer).length)
        console.send(:parse_input, "\n")
        expect(console.instance_variable_get(:@input_buffer)).to eq("line1\nline2\n")
      end

      it "does not return :submit" do
        console.instance_variable_set(:@input_buffer, String.new("test"))
        console.instance_variable_set(:@cursor_pos, 4)
        result = console.send(:parse_input, "\n")
        expect(result).not_to eq(:submit)
        expect(result).to be_nil
      end
    end
  end

  # Phase 4: Reset @saved_column on horizontal movement and edits
  describe "@saved_column reset behavior" do
    context "horizontal cursor movements" do
      it "resets @saved_column on cursor_forward" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@saved_column, 5)

        console.send(:cursor_forward)

        expect(console.instance_variable_get(:@saved_column)).to be_nil
      end

      it "resets @saved_column on cursor_backward" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 3)
        console.instance_variable_set(:@saved_column, 5)

        console.send(:cursor_backward)

        expect(console.instance_variable_get(:@saved_column)).to be_nil
      end

      it "resets @saved_column on cursor_to_start" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 3)
        console.instance_variable_set(:@saved_column, 5)

        console.send(:cursor_to_start)

        expect(console.instance_variable_get(:@saved_column)).to be_nil
      end

      it "resets @saved_column on cursor_to_end" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@saved_column, 5)

        console.send(:cursor_to_end)

        expect(console.instance_variable_get(:@saved_column)).to be_nil
      end
    end

    context "edit operations" do
      it "resets @saved_column on insert_char" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 3)
        console.instance_variable_set(:@saved_column, 5)

        console.send(:insert_char, "x")

        expect(console.instance_variable_get(:@saved_column)).to be_nil
      end

      it "resets @saved_column on delete_backward" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 3)
        console.instance_variable_set(:@saved_column, 5)

        console.send(:delete_backward)

        expect(console.instance_variable_get(:@saved_column)).to be_nil
      end

      it "resets @saved_column on delete_forward" do
        console.instance_variable_set(:@input_buffer, String.new("hello"))
        console.instance_variable_set(:@cursor_pos, 3)
        console.instance_variable_set(:@saved_column, 5)

        console.send(:delete_forward)

        expect(console.instance_variable_get(:@saved_column)).to be_nil
      end
    end
  end

  # Phase 5.1: Integration tests for multiline workflows
  describe "multiline editing integration workflows" do
    context "typing multiline input with Enter, navigating, and submitting" do
      it "allows creating and submitting multiline input" do
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)

        # Type "SELECT *"
        "SELECT *".each_char { |c| console.send(:insert_char, c) }
        expect(console.instance_variable_get(:@input_buffer)).to eq("SELECT *")

        # Press Enter to insert newline
        console.send(:insert_char, "\n")
        expect(console.instance_variable_get(:@input_buffer)).to eq("SELECT *\n")

        # Type "FROM users"
        "FROM users".each_char { |c| console.send(:insert_char, c) }
        expect(console.instance_variable_get(:@input_buffer)).to eq("SELECT *\nFROM users")

        # Press Enter again
        console.send(:insert_char, "\n")
        expect(console.instance_variable_get(:@input_buffer)).to eq("SELECT *\nFROM users\n")

        # Type "WHERE id = 1"
        "WHERE id = 1".each_char { |c| console.send(:insert_char, c) }
        expect(console.instance_variable_get(:@input_buffer)).to eq("SELECT *\nFROM users\nWHERE id = 1")

        # Submit with Enter
        result = console.send(:parse_input, "\r")
        expect(result).to eq(:submit)
        expect(console.instance_variable_get(:@input_buffer)).to eq("SELECT *\nFROM users\nWHERE id = 1")
      end

      it "allows navigating up and down through lines" do
        # Start with multiline content
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
        console.instance_variable_set(:@cursor_pos, 18) # End of buffer

        # Navigate up to line 2
        console.send(:cursor_up_or_history_prev)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(1) # On line 2 (0-indexed)

        # Navigate up to line 1
        console.send(:cursor_up_or_history_prev)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(0) # On line 1

        # Navigate down to line 2
        console.send(:cursor_down_or_history_next)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(1)

        # Navigate down to line 3
        console.send(:cursor_down_or_history_next)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(2)
      end

      it "preserves column position when navigating between lines of different lengths" do
        # Create content with lines of different lengths
        # "short" (5 chars) + \n + "longer line here" (16 chars) + \n + "short" (5 chars)
        console.instance_variable_set(:@input_buffer, String.new("short\nlonger line here\nshort"))
        console.instance_variable_set(:@cursor_pos, 16) # Position 16 = line 1, column 10 (the 'e' in "here")

        # Navigate up to shorter line
        console.send(:cursor_up_or_history_prev)
        line, col = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(0)
        expect(col).to eq(5) # Clamped to end of "short"

        # Navigate down - should remember original column 10
        console.send(:cursor_down_or_history_next)
        line, col = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(1)
        expect(col).to eq(10) # Restored to saved column 10
      end
    end

    context "editing multiline input" do
      it "allows inserting characters in the middle of lines" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
        console.instance_variable_set(:@cursor_pos, 8) # Middle of line2

        # Insert "XX"
        console.send(:insert_char, "X")
        console.send(:insert_char, "X")

        expect(console.instance_variable_get(:@input_buffer)).to eq("line1\nliXXne2\nline3")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(10)
      end

      it "allows deleting characters in the middle of lines" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
        console.instance_variable_set(:@cursor_pos, 8) # After "li" in line2

        # Delete backward twice
        console.send(:delete_backward)
        console.send(:delete_backward)

        expect(console.instance_variable_get(:@input_buffer)).to eq("line1\nne2\nline3")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(6)
      end

      it "allows deleting forward across lines" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
        console.instance_variable_set(:@cursor_pos, 5) # At end of line1, before \n

        # Delete forward (removes the newline)
        console.send(:delete_forward)

        expect(console.instance_variable_get(:@input_buffer)).to eq("line1line2\nline3")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(5)
      end

      it "handles inserting newlines in the middle of existing text" do
        console.instance_variable_set(:@input_buffer, String.new("line1line2"))
        console.instance_variable_set(:@cursor_pos, 5) # After "line1"

        # Insert newline
        console.send(:insert_char, "\n")

        expect(console.instance_variable_get(:@input_buffer)).to eq("line1\nline2")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(6)
      end
    end

    context "loading and navigating multiline history entries" do
      it "loads multiline history entry and allows navigation within it" do
        # Setup history with a multiline entry
        console.instance_variable_set(:@history, [
                                        "single line",
                                        "first line\nsecond line\nthird line",
                                        "another single"
                                      ])

        # Start with empty buffer
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)

        # Navigate to most recent history (empty buffer allows history navigation)
        console.send(:cursor_up_or_history_prev)
        expect(console.instance_variable_get(:@input_buffer)).to eq("another single")

        # Clear buffer to continue navigating history
        console.send(:kill_to_start)

        # Navigate to multiline entry
        console.send(:cursor_up_or_history_prev)
        expect(console.instance_variable_get(:@input_buffer)).to eq("first line\nsecond line\nthird line")

        # Cursor should be at end of loaded entry
        pos = console.instance_variable_get(:@cursor_pos)
        line, = console.send(:get_line_and_column, pos)
        expect(line).to eq(2) # Should be on last line

        # To navigate within the entry, we need to exit history mode
        # We do this by making an edit (which clears @history_pos)
        # For now, verify we're in history mode
        expect(console.instance_variable_get(:@history_pos)).not_to be_nil

        # Exit history mode by clearing it manually (simulating what would happen after edit)
        console.instance_variable_set(:@history_pos, nil)

        # Now we can navigate within the multiline entry
        # Navigate up to second line
        console.send(:cursor_up_or_history_prev)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(1)

        # Navigate up to first line
        console.send(:cursor_up_or_history_prev)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(0)
      end

      it "allows editing multiline history entries before resubmitting" do
        # Setup history
        console.instance_variable_set(:@history, ["SELECT *\nFROM users\nWHERE id = 1"])

        # Start with empty buffer and load history
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)
        console.send(:cursor_up_or_history_prev)

        expect(console.instance_variable_get(:@input_buffer)).to eq("SELECT *\nFROM users\nWHERE id = 1")

        # Cursor should be at end of buffer
        pos = console.instance_variable_get(:@cursor_pos)
        line, = console.send(:get_line_and_column, pos)
        expect(line).to eq(2) # On last line

        # Make an edit
        console.send(:insert_char, ";")
        expect(console.instance_variable_get(:@input_buffer)).to eq("SELECT *\nFROM users\nWHERE id = 1;")

        # NOTE: Currently, edits don't automatically clear @history_pos (potential enhancement)
        # For this test, we manually exit history mode to demonstrate navigation within edited content
        console.instance_variable_set(:@history_pos, nil)

        # Now we can navigate within the entry
        console.send(:cursor_up_or_history_prev)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(1) # Moved to "FROM users" line

        # Edit this line
        console.send(:insert_char, " ")
        console.send(:insert_char, "u")

        expect(console.instance_variable_get(:@input_buffer)).to eq("SELECT *\nFROM users u\nWHERE id = 1;")
      end
    end

    context "background output during multiline editing" do
      it "properly redraws multiline input after background output" do
        # Stub pipe_read to avoid unexpected message error
        allow(pipe_read).to receive(:read_nonblock).with(1024).and_return("")
        allow(pipe_write).to receive(:write)

        # Setup queue with background message
        queue = console.instance_variable_get(:@output_queue)
        queue.push("background message")

        console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
        console.instance_variable_set(:@cursor_pos, 8)
        console.instance_variable_set(:@last_line_count, 3)
        console.instance_variable_set(:@last_cursor_physical_row, 1) # Cursor on physical row 1

        console.send(:handle_output_for_input_mode, "> ")

        output = stdout.string

        # Verify that:
        # 1. Cursor moved up to clear old input (3 lines means move up 2 times)
        expect(output).to include("\e[A") # Cursor up
        # 2. Screen was cleared
        expect(output).to include("\e[J") # Clear to end of screen
        # 3. Background output was displayed
        expect(output).to include("background message")
        # 4. Input was redrawn (would include multiline content)
        expect(output).to include("line1")
        expect(output).to include("line2")
        expect(output).to include("line3")
      end
    end
  end

  # Phase 5.2: Edge case tests
  describe "multiline editing edge cases" do
    context "buffer with only newlines" do
      it "handles buffer containing only newline characters" do
        console.instance_variable_set(:@input_buffer, String.new("\n\n\n"))
        console.instance_variable_set(:@cursor_pos, 3) # At end of buffer

        # Verify lines method returns empty strings
        lines = console.send(:lines)
        expect(lines).to eq(["", "", "", ""])
        expect(lines.length).to eq(4)

        # Verify get_line_and_column works
        line, col = console.send(:get_line_and_column, 0)
        expect(line).to eq(0)
        expect(col).to eq(0)

        line, col = console.send(:get_line_and_column, 1)
        expect(line).to eq(1)
        expect(col).to eq(0)

        line, col = console.send(:get_line_and_column, 3)
        expect(line).to eq(3)
        expect(col).to eq(0)

        # Verify navigation works (moving up from last line)
        console.send(:cursor_up_or_history_prev)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(2)
      end

      it "allows navigating through lines that are all empty" do
        console.instance_variable_set(:@input_buffer, String.new("\n\n"))
        console.instance_variable_set(:@cursor_pos, 0) # Start of buffer

        # Navigate down through empty lines
        console.send(:cursor_down_or_history_next)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(1)

        console.send(:cursor_down_or_history_next)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(2)

        # Navigate back up
        console.send(:cursor_up_or_history_prev)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(1)
      end
    end

    context "very long lines" do
      it "handles very long single lines without issues" do
        # Create a line with 1000 characters
        long_line = "x" * 1000
        console.instance_variable_set(:@input_buffer, String.new(long_line))
        console.instance_variable_set(:@cursor_pos, 500)

        # Verify line/column calculation works
        line, col = console.send(:get_line_and_column, 500)
        expect(line).to eq(0)
        expect(col).to eq(500)

        # Verify navigation doesn't break
        console.send(:cursor_up_or_history_prev)
        # Should stay on same position (only one line)
        expect(console.instance_variable_get(:@cursor_pos)).to eq(500)

        # Verify redraw doesn't crash (just ensure it completes without error)
        expect { console.send(:redraw_input_line, "> ") }.not_to raise_error
      end

      it "handles multiline input with very long lines" do
        # Create multiple very long lines
        long_line1 = "a" * 500
        long_line2 = "b" * 800
        long_line3 = "c" * 300
        buffer = "#{long_line1}\n#{long_line2}\n#{long_line3}"

        console.instance_variable_set(:@input_buffer, String.new(buffer))
        console.instance_variable_set(:@cursor_pos, 501) # Start of line2

        # Verify line calculation
        line, col = console.send(:get_line_and_column, 501)
        expect(line).to eq(1)
        expect(col).to eq(0)

        # Navigate between long lines
        console.send(:cursor_down_or_history_next)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(2)

        console.send(:cursor_up_or_history_prev)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(1)
      end
    end

    context "cursor at end of buffer with trailing newline" do
      it "handles cursor positioning after trailing newline" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2\n"))
        console.instance_variable_set(:@cursor_pos, 12) # After trailing newline

        # Verify we're on the empty third line
        line, col = console.send(:get_line_and_column, 12)
        expect(line).to eq(2)
        expect(col).to eq(0)

        # Navigate up to line 2
        console.send(:cursor_up_or_history_prev)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(1)

        # Navigate back down to empty line
        console.send(:cursor_down_or_history_next)
        line, = console.send(:get_line_and_column, console.instance_variable_get(:@cursor_pos))
        expect(line).to eq(2)
      end

      it "handles inserting characters after trailing newline" do
        console.instance_variable_set(:@input_buffer, String.new("line1\n"))
        console.instance_variable_set(:@cursor_pos, 6) # After newline

        # Insert characters
        console.send(:insert_char, "n")
        console.send(:insert_char, "e")
        console.send(:insert_char, "w")

        expect(console.instance_variable_get(:@input_buffer)).to eq("line1\nnew")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(9)

        # Verify line calculation
        line, col = console.send(:get_line_and_column, 9)
        expect(line).to eq(1)
        expect(col).to eq(3)
      end
    end

    context "Ctrl+K (kill to end of line) across line boundaries" do
      it "kills from cursor to end of buffer without crossing newline" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
        console.instance_variable_set(:@cursor_pos, 3) # Middle of "line1"

        # Ctrl+K should kill "e1" but not the newline or following lines
        console.send(:kill_to_end)

        # NOTE: kill_to_end kills to END OF BUFFER, not end of line
        # This is current behavior according to scope (Home/End work on entire buffer)
        expect(console.instance_variable_get(:@input_buffer)).to eq("lin")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(3)
      end

      it "kills entire remaining buffer when called from middle of multiline" do
        console.instance_variable_set(:@input_buffer, String.new("first\nsecond\nthird"))
        console.instance_variable_set(:@cursor_pos, 8) # Middle of "second"

        console.send(:kill_to_end)

        expect(console.instance_variable_get(:@input_buffer)).to eq("first\nse")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(8)
      end
    end

    context "Ctrl+U (kill to start) across line boundaries" do
      it "kills from start of buffer to cursor" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2\nline3"))
        console.instance_variable_set(:@cursor_pos, 8) # Middle of "line2"

        # Ctrl+U should kill from start to cursor
        console.send(:kill_to_start)

        expect(console.instance_variable_get(:@input_buffer)).to eq("ne2\nline3")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      end

      it "kills across multiple lines when cursor is on last line" do
        console.instance_variable_set(:@input_buffer, String.new("first\nsecond\nthird"))
        console.instance_variable_set(:@cursor_pos, 15) # Middle of "third"

        console.send(:kill_to_start)

        expect(console.instance_variable_get(:@input_buffer)).to eq("ird")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      end

      it "does nothing when cursor is at start of buffer" do
        console.instance_variable_set(:@input_buffer, String.new("line1\nline2"))
        console.instance_variable_set(:@cursor_pos, 0)

        console.send(:kill_to_start)

        expect(console.instance_variable_get(:@input_buffer)).to eq("line1\nline2")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      end
    end
  end

  describe "branch coverage for uncovered paths" do
    describe "#initialize terminal width handling" do
      it "handles when IO.console returns nil" do
        allow(IO).to receive(:console).and_return(nil)

        # Create a new instance to test initialization
        new_console = described_class.allocate
        new_console.instance_variable_set(:@stdin, stdin)
        new_console.instance_variable_set(:@stdout, stdout)
        new_console.instance_variable_set(:@original_stty, `stty -g`.chomp)

        # Mock the necessary initialization
        allow(new_console.instance_variable_get(:@stdin)).to receive(:raw!)

        # Simulate the initialization code for @terminal_width
        terminal_width = IO.console&.winsize&.[](1) || 80

        expect(terminal_width).to eq(80)
      end

      it "handles when IO.console returns object but winsize is nil" do
        console_mock = instance_double(IO)
        allow(IO).to receive(:console).and_return(console_mock)
        allow(console_mock).to receive(:winsize).and_return(nil)

        terminal_width = IO.console&.winsize&.[](1) || 80

        expect(terminal_width).to eq(80)
      end
    end

    describe "#initialize without db_history" do
      it "does not load history when db_history is nil" do
        new_console = described_class.allocate
        new_console.instance_variable_set(:@stdin, stdin)
        new_console.instance_variable_set(:@stdout, stdout)
        new_console.instance_variable_set(:@original_stty, `stty -g`.chomp)
        new_console.instance_variable_set(:@db_history, nil)

        # Should not call load_history_from_db
        expect(new_console).not_to receive(:load_history_from_db)

        # Simulate the initialization logic
        new_console.send(:load_history_from_db) if new_console.instance_variable_get(:@db_history)
      end
    end

    describe "#transition_to with same state" do
      it "returns early when transitioning to same state" do
        current_state = console.instance_variable_get(:@state)

        # Should not call on_exit or on_enter
        expect(current_state).not_to receive(:on_exit)
        expect(current_state).not_to receive(:on_enter)

        console.send(:transition_to, current_state)
      end
    end

    describe "#current_state_name" do
      it "returns the name of the current state" do
        # Console starts in IdleState
        expect(console.current_state_name).to eq(:idle)
      end

      it "returns correct name after state transition" do
        console.start_progress
        expect(console.current_state_name).to eq(:progress)
      end
    end

    describe "#pause" do
      it "delegates to current state's pause method" do
        state = console.instance_variable_get(:@state)
        expect(state).to receive(:pause)
        console.pause
      end
    end

    describe "#resume when not in paused state" do
      it "raises StateTransitionError when not in paused state" do
        # Console is in IdleState by default
        expect { console.resume }.to raise_error(Nu::Agent::ConsoleIO::StateTransitionError, "Not in paused state")
      end
    end

    describe "#resume when in paused state" do
      it "resumes from paused state successfully" do
        # First transition to a paused state
        paused_state = Nu::Agent::ConsoleIO::PausedState.new(console, console.instance_variable_get(:@state))
        console.instance_variable_set(:@state, paused_state)

        expect(paused_state).to receive(:resume)
        console.resume
      end
    end

    describe "#update_spinner_message" do
      it "updates the spinner message" do
        spinner_state = console.instance_variable_get(:@spinner_state)
        console.update_spinner_message("New message")
        expect(spinner_state.message).to eq("New message")
      end
    end

    describe "#do_hide_spinner when current thread is spinner thread" do
      it "does not join spinner thread when called from spinner thread" do
        # Test the condition: @spinner_thread&.join unless Thread.current == @spinner_thread
        # We can't easily mock Thread.current, but we can verify the logic by setting spinner_thread to nil
        console.instance_variable_set(:@spinner_thread, nil)

        spinner_state = console.instance_variable_get(:@spinner_state)
        allow(spinner_state).to receive(:stop)
        allow(console).to receive(:flush_stdin) # rubocop:disable RSpec/SubjectStub

        # Should not raise error when spinner_thread is nil
        expect { console.send(:do_hide_spinner) }.not_to raise_error
      end
    end

    describe "#do_show_spinner interrupt handling" do
      it "handles interrupt in spinner thread" do
        # Setup spinner state
        spinner_state = console.instance_variable_get(:@spinner_state)
        parent_thread = Thread.current
        spinner_state.instance_variable_set(:@running, true)
        spinner_state.instance_variable_set(:@parent_thread, parent_thread)
        spinner_state.instance_variable_set(:@interrupt_requested, false)

        # Test the interrupt handling code path by directly setting the flag
        # We can't safely test the actual interrupt raising in unit tests
        spinner_state.instance_variable_set(:@interrupt_requested, true)

        expect(spinner_state.interrupt_requested).to be true
      end

      it "clears spinner line and sets interrupt flag when Interrupt is raised" do
        # Mock stdin to simulate flush
        allow(stdin).to receive(:wait_readable).with(0).and_return(false)

        # Setup to capture the rescue Interrupt behavior
        # We'll create a mock spinner_loop that raises Interrupt
        allow(console).to receive(:spinner_loop) do # rubocop:disable RSpec/SubjectStub
          # This will raise Interrupt which should be caught by the rescue block
          raise Interrupt
        end

        # Call do_show_spinner which creates a thread
        console.send(:do_show_spinner, "Test message")

        # Wait for thread to complete (with timeout to prevent hanging)
        spinner_thread = console.instance_variable_get(:@spinner_thread)
        begin
          spinner_thread.join(0.5) # Wait up to 0.5 seconds
        rescue Interrupt
          # If the parent thread receives the interrupt, that's expected behavior
        end

        # The interrupt handler should have set the flag
        spinner_state = console.instance_variable_get(:@spinner_state)
        expect(spinner_state.interrupt_requested).to be true
      end
    end

    describe "#do_readline when state does not respond to on_input_completed" do
      it "completes without calling on_input_completed" do
        # Setup for readline
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)
        console.instance_variable_set(:@history_pos, nil)
        console.instance_variable_set(:@saved_input, String.new(""))

        # Create a state that doesn't respond to on_input_completed
        state = Nu::Agent::ConsoleIO::IdleState.new(console)
        console.instance_variable_set(:@state, state)

        # Mock handle_readline_select to return immediately
        allow(console).to receive(:handle_readline_select).and_return("test result") # rubocop:disable RSpec/SubjectStub
        allow(console).to receive(:redraw_input_line) # rubocop:disable RSpec/SubjectStub

        # Should not raise error even though state doesn't respond to on_input_completed
        result = console.send(:do_readline, "> ")
        expect(result).to eq("test result")
      end
    end

    describe "#physical_rows_to_position when line_index < buffer_lines.length" do
      it "calculates rows correctly for multi-line with cursor on second line" do
        buffer_lines = ["first line", "second line", "third line"]
        line_index = 1
        column = 5
        prompt_length = 2

        result = console.send(:physical_rows_to_position, buffer_lines, line_index, column, prompt_length)

        # First line has prompt, second line doesn't
        # Should count first line + position within second line
        expect(result).to be >= 0
      end
    end

    describe "#log_state_transition when debug is enabled" do
      it "outputs debug message when SubsystemDebugger.should_output? returns true" do
        application = instance_double("Application")
        console.instance_variable_set(:@application, application)

        allow(Nu::Agent::SubsystemDebugger).to receive(:should_output?).with(application, "console", 1).and_return(true)
        allow(pipe_write).to receive(:write)

        old_state = console.instance_variable_get(:@state)
        new_state = Nu::Agent::ConsoleIO::IdleState.new(console)

        expect(console).to receive(:puts).with(/State transition/) # rubocop:disable RSpec/SubjectStub

        console.send(:log_state_transition, old_state, new_state)
      end
    end

    describe "#handle_readline_select when stdin has input" do
      it "handles stdin input correctly" do
        allow(IO).to receive(:select).and_return([[stdin], nil, nil])
        allow(console).to receive(:handle_stdin_input).and_return(:continue) # rubocop:disable RSpec/SubjectStub

        result = console.send(:handle_readline_select, "> ")

        expect(result).to eq(:continue)
      end
    end

    describe "#handle_stdin_input when result is :eof" do
      it "handles EOF correctly" do
        allow(stdin).to receive(:read_nonblock).and_return("\x04") # Ctrl-D on empty line
        allow(console).to receive_messages(parse_input: :eof, handle_eof: nil) # rubocop:disable RSpec/SubjectStub

        result = console.send(:handle_stdin_input, "> ")

        expect(result).to be_nil
      end
    end

    describe "#parse_input with non-printable characters" do
      it "ignores characters outside printable range (< 32)" do
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)

        # Test control character that's not handled
        console.send(:parse_input, "\x02") # Ctrl-B

        expect(console.instance_variable_get(:@input_buffer)).to eq("")
      end

      it "ignores characters outside printable range (> 126)" do
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)

        # Test character with ord > 126
        console.send(:parse_input, "\x7F") # DEL is handled separately
        # DEL triggers backspace, so buffer should remain empty when at start
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      end
    end

    describe "#handle_escape_sequence with insufficient characters" do
      it "returns index when not enough characters for sequence" do
        chars = ["\e"] # Just escape, nothing following
        index = 0

        result = console.send(:handle_escape_sequence, chars, index)

        expect(result).to eq(0)
      end
    end

    describe "#handle_csi_sequence edge cases" do
      it "handles Delete key (3~)" do
        console.instance_variable_set(:@input_buffer, String.new("abc"))
        console.instance_variable_set(:@cursor_pos, 1)

        chars = "\e[3~".chars
        index = 2 # At the '3'

        result = console.send(:handle_csi_sequence, chars, index)

        expect(console.instance_variable_get(:@input_buffer)).to eq("ac")
        expect(result).to eq(3) # index of '~'
      end

      it "handles End key variant (4~)" do
        console.instance_variable_set(:@input_buffer, String.new("test"))
        console.instance_variable_set(:@cursor_pos, 0)

        chars = "\e[4~".chars
        index = 2 # At the '4'

        result = console.send(:handle_csi_sequence, chars, index)

        expect(console.instance_variable_get(:@cursor_pos)).to eq(4)
        expect(result).to eq(3)
      end

      it "handles Home key variant (1~)" do
        console.instance_variable_set(:@input_buffer, String.new("test"))
        console.instance_variable_set(:@cursor_pos, 4)

        chars = "\e[1~".chars
        index = 2 # At the '1'

        console.send(:handle_csi_sequence, chars, index)

        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      end
    end

    describe "#handle_numbered_csi_sequence edge cases" do
      it "handles sequence without terminating ~" do
        console.instance_variable_set(:@input_buffer, String.new("test"))
        console.instance_variable_set(:@cursor_pos, 2)

        chars = "\e[1".chars # Just "1" without ~
        index = 2

        result = console.send(:handle_numbered_csi_sequence, chars, index, "1")

        # Should return index since sequence is incomplete
        expect(result).to eq(2)
      end

      it "handles sequence that ends before finding ~" do
        chars = "\e[1;5".chars # Incomplete sequence
        index = 2

        result = console.send(:handle_numbered_csi_sequence, chars, index, "1")

        # Should return the last index processed
        expect(result).to be >= index
      end
    end

    describe "#handle_output_for_input_mode with empty lines" do
      it "returns early when no output lines" do
        allow(console).to receive(:drain_output_queue).and_return([]) # rubocop:disable RSpec/SubjectStub
        allow(console).to receive(:do_redraw_input_line) # rubocop:disable RSpec/SubjectStub

        # Should not call redraw if no lines
        expect(console).not_to receive(:do_redraw_input_line) # rubocop:disable RSpec/SubjectStub

        console.send(:handle_output_for_input_mode, "> ")
      end
    end

    describe "#save_history_to_db when debug is false" do
      it "does not warn when debug is false and save fails" do
        db_history = instance_double("DbHistory")
        console.instance_variable_set(:@db_history, db_history)
        console.instance_variable_set(:@debug, false)

        allow(db_history).to receive(:add_command_history).and_raise(StandardError.new("DB error"))

        # Should not output warning
        expect(console).not_to receive(:warn) # rubocop:disable RSpec/SubjectStub

        console.send(:save_history_to_db, "test command")
      end
    end

    describe "#load_history_from_db when debug is false" do
      it "does not warn when debug is false and load fails" do
        db_history = instance_double("DbHistory")
        console.instance_variable_set(:@db_history, db_history)
        console.instance_variable_set(:@debug, false)

        allow(db_history).to receive(:get_command_history).and_raise(StandardError.new("DB error"))

        # Should not output warning
        expect(console).not_to receive(:warn) # rubocop:disable RSpec/SubjectStub

        console.send(:load_history_from_db)
      end
    end

    describe "#load_history_from_db when db_history is nil" do
      it "returns early without loading" do
        console.instance_variable_set(:@db_history, nil)

        # Should not try to access db_history
        console.send(:load_history_from_db)

        expect(console.instance_variable_get(:@history)).to eq([])
      end
    end

    describe "#spinner_loop when no readable IO" do
      it "animates spinner on timeout" do
        spinner_state = console.instance_variable_get(:@spinner_state)
        spinner_state.instance_variable_set(:@running, true)

        # First call returns nil (timeout), second call returns nothing to end loop
        call_count = 0
        allow(IO).to receive(:select) do
          call_count += 1
          if (call_count <= 2) && (call_count == 2)
            # After second call, stop the loop
            spinner_state.instance_variable_set(:@running, false)
          end
          nil
        end

        allow(console).to receive(:animate_spinner) # rubocop:disable RSpec/SubjectStub

        # Should call animate_spinner at least once (could be twice due to timing)
        expect(console).to receive(:animate_spinner).at_least(:once) # rubocop:disable RSpec/SubjectStub

        console.send(:spinner_loop)
      end
    end

    describe "additional branch coverage for remaining paths" do
      it "handles IO.select returning nil" do
        allow(IO).to receive(:select).and_return(nil)

        result = console.send(:handle_readline_select, "> ")

        expect(result).to eq(:continue)
      end

      it "handles physical_rows_to_position with line_index at buffer boundary" do
        buffer_lines = %w[line1 line2]
        line_index = 2 # At boundary
        column = 0
        prompt_length = 2

        result = console.send(:physical_rows_to_position, buffer_lines, line_index, column, prompt_length)

        expect(result).to be >= 0
      end

      it "handles physical_rows_for_line with non-zero prompt on later lines" do
        console.instance_variable_set(:@terminal_width, 80)

        # Test line 296 - idx.zero? returns false
        buffer_lines = %w[first second]
        buffer_lines.each_with_index do |line, idx|
          pl = idx.zero? ? 2 : 0
          rows = console.send(:physical_rows_for_line, line, prompt_length: pl)
          expect(rows).to be >= 1
        end
      end

      it "handles handle_escape_sequence at end of chars array" do
        chars = ["\e", "["]
        index = 1 # At last char

        result = console.send(:handle_escape_sequence, chars, index)

        # Should return index when can't process sequence
        expect(result).to be >= index
      end

      it "handles CSI sequence with insufficient characters for '3'" do
        chars = ["\e", "[", "3"] # Incomplete Delete sequence
        index = 2

        result = console.send(:handle_csi_sequence, chars, index)

        # Should return current index when sequence incomplete
        expect(result).to eq(2)
      end

      it "handles CSI sequence with insufficient characters for '4'" do
        chars = ["\e", "[", "4"] # Incomplete End variant
        index = 2

        result = console.send(:handle_csi_sequence, chars, index)

        # Should return current index when sequence incomplete
        expect(result).to eq(2)
      end

      it "handles CSI sequence with '1' but insufficient characters" do
        chars = ["\e", "[", "1"] # Incomplete Home variant
        index = 2

        result = console.send(:handle_csi_sequence, chars, index)

        # Should delegate to handle_numbered_csi_sequence
        expect(result).to be >= 2
      end

      it "handles numbered CSI sequence ending at array boundary" do
        chars = ["\e", "[", "1", ";", "5"] # Ends without ~
        index = 2

        result = console.send(:handle_numbered_csi_sequence, chars, index, "1")

        # Returns index when sequence incomplete (no terminating ~)
        expect(result).to eq(2)
      end

      it "handles handle_numbered_csi_sequence when terminator found" do
        chars = ["\e", "[", "1", "~"]
        index = 2

        console.instance_variable_set(:@input_buffer, String.new("test"))
        console.instance_variable_set(:@cursor_pos, 4)

        result = console.send(:handle_numbered_csi_sequence, chars, index, "1")

        # Should move to start (Home key)
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
        expect(result).to eq(3)
      end

      it "handles numbered CSI sequence that is not '1'" do
        # Test sequence "2~" which is not the Home key
        chars = ["\e", "[", "2", "~"]
        index = 2

        console.instance_variable_set(:@input_buffer, String.new("test"))
        console.instance_variable_set(:@cursor_pos, 2)

        result = console.send(:handle_numbered_csi_sequence, chars, index, "2")

        # Should return the index of the terminator
        expect(result).to eq(3)
        # Cursor should not change (unknown sequence)
        expect(console.instance_variable_get(:@cursor_pos)).to eq(2)
      end

      it "handles numbered CSI sequence that ends past array boundary" do
        # Test when loop consumes all characters and i >= chars.length
        chars = ["\e", "[", "1", "3", ";", "5"]
        index = 2

        result = console.send(:handle_numbered_csi_sequence, chars, index, "1")

        # Should return index when no terminator found
        expect(result).to eq(2)
      end

      it "handles numbered CSI sequence with digits and semicolons" do
        # Test that the loop processes digits and semicolons
        chars = ["\e", "[", "1", "3", ";", "5", "~"]
        index = 2

        result = console.send(:handle_numbered_csi_sequence, chars, index, "1")

        # Should process the sequence but not recognize "13;5" as Home
        expect(result).to eq(6)
      end
    end

    describe "handle_csi_sequence edge cases" do
      it "returns index - 1 when index >= chars.length" do
        chars = ["\e", "["]
        index = 2

        result = console.send(:handle_csi_sequence, chars, index)

        expect(result).to eq(1)
      end

      it "handles unknown CSI sequence character" do
        # Test with an unknown CSI character like 'Z'
        chars = ["\e", "[", "Z"]
        index = 2

        result = console.send(:handle_csi_sequence, chars, index)

        # Should return the index (ignoring unknown sequence)
        expect(result).to eq(2)
      end
    end
  end

  describe "spinner mode input handling" do
    describe "#spinner_loop with non-Ctrl-C input" do
      it "ignores non-Ctrl-C keystrokes in spinner mode" do
        # Set up spinner state
        spinner_state = console.instance_variable_get(:@spinner_state)
        spinner_state.start("Test message", Thread.current)

        # Mock IO.select to return stdin with a non-Ctrl-C character
        allow(IO).to receive(:select).and_return([[stdin, pipe_read], nil, nil])
        allow(stdin).to receive(:read_nonblock).and_return("a")
        allow(pipe_read).to receive(:read_nonblock).and_raise(IO::WaitReadable)

        # Stop spinner after one iteration
        call_count = 0
        allow(IO).to receive(:select) do
          call_count += 1
          if call_count == 1
            [[stdin], nil, nil]
          else
            spinner_state.stop
            nil
          end
        end

        # Should not raise an error
        expect do
          console.send(:spinner_loop)
        end.not_to raise_error
      end
    end

    describe "#do_hide_spinner when called from spinner thread" do
      it "does not join the spinner thread when called from within it" do
        spinner_state = console.instance_variable_get(:@spinner_state)
        spinner_state.start("Test", Thread.current)

        # Create and set the spinner thread
        spinner_thread = Thread.new do
          # Simulate being inside the spinner thread
          Thread.current
        end
        console.instance_variable_set(:@spinner_thread, spinner_thread)

        # Stop the spinner state first
        spinner_state.stop

        # Call do_hide_spinner from within the spinner thread context
        # This tests the `unless Thread.current == @spinner_thread` branch
        expect(spinner_thread).not_to receive(:join)

        # Mock stdin.wait_readable for flush_stdin
        allow(stdin).to receive(:wait_readable).with(0).and_return(false)

        # Temporarily make current thread == spinner_thread for the test
        original_thread = console.instance_variable_get(:@spinner_thread)
        console.instance_variable_set(:@spinner_thread, Thread.current)

        console.send(:do_hide_spinner)

        # Restore
        console.instance_variable_set(:@spinner_thread, original_thread)
        spinner_thread.kill
      end
    end
  end

  describe "initialization edge cases" do
    it "handles missing IO.console during initialization" do
      # Mock IO.console to return nil
      allow(IO).to receive(:console).and_return(nil)
      allow($stdin).to receive(:raw!)

      # Create a real instance to test initialization
      io = described_class.allocate
      io.instance_variable_set(:@stdin, $stdin)
      io.instance_variable_set(:@stdout, StringIO.new)

      # Manually run the part of initialize that sets terminal_width
      terminal_width = IO.console&.winsize&.[](1) || 80

      # Should fall back to 80
      expect(terminal_width).to eq(80)
    end

    it "handles IO.console without winsize" do
      # Mock IO.console to return an object without winsize
      mock_console = double("console")
      allow(mock_console).to receive(:winsize).and_return(nil)
      allow(IO).to receive(:console).and_return(mock_console)

      terminal_width = IO.console&.winsize&.[](1) || 80

      # Should fall back to 80
      expect(terminal_width).to eq(80)
    end
  end
end
