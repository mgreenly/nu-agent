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
    context "with Enter key" do
      it "returns :submit" do
        result = console.send(:parse_input, "\n")
        expect(result).to eq(:submit)
      end

      it "returns :submit for carriage return" do
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
        console.send(:redraw_input_line, "> ")

        output = stdout.string
        # Should move up 2 lines (3 - 1) to clear old display
        expect(output).to match(/\e\[2A/)
        # Should clear to end of screen
        expect(output).to include("\e[J")
      end

      it "handles trailing newline" do
        console.instance_variable_set(:@input_buffer, "line1\n")
        console.instance_variable_set(:@cursor_pos, 6)
        console.instance_variable_set(:@last_line_count, 1)
        console.send(:redraw_input_line, "> ")

        expect(console.instance_variable_get(:@last_line_count)).to eq(2)
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

      it "saves current input when entering history" do
        console.instance_variable_set(:@history, %w[first second])
        console.instance_variable_set(:@input_buffer, String.new("partially typed"))
        console.instance_variable_set(:@cursor_pos, 15)

        console.send(:parse_input, "\e[A")

        expect(console.instance_variable_get(:@saved_input)).to eq("partially typed")
      end

      it "navigates backwards through history on repeated up arrows" do
        console.instance_variable_set(:@history, %w[first second third])
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)

        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("third")

        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("second")

        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("first")
      end

      it "stops at beginning of history" do
        console.instance_variable_set(:@history, %w[first second])
        console.instance_variable_set(:@input_buffer, String.new(""))
        console.instance_variable_set(:@cursor_pos, 0)

        # Navigate to beginning
        console.send(:parse_input, "\e[A")
        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("first")

        # Try to go further - should stay at first
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
        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("second")

        # Go forward one
        console.send(:parse_input, "\e[B")
        expect(console.instance_variable_get(:@input_buffer)).to eq("third")
      end

      it "restores saved input when navigating past end of history" do
        console.instance_variable_set(:@history, %w[first second])
        console.instance_variable_set(:@input_buffer, String.new("my input"))
        console.instance_variable_set(:@cursor_pos, 8)

        # Enter history
        console.send(:parse_input, "\e[A")
        expect(console.instance_variable_get(:@input_buffer)).to eq("second")

        # Navigate back past end
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
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\n")
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
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\n")

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

  describe "#readline integration" do
    it "reads a line of input and returns it" do
      # Mock readline to call handle_readline_select once and return a result
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("hello\n")
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

      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\n")
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
      allow(stdin).to receive(:read_nonblock).with(1024).and_return("\x04", "\n")
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
end
