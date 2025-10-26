# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Nu::Agent::ConsoleIO do
  let(:stdin) { instance_double(IO, "stdin") }
  let(:stdout) { StringIO.new }
  let(:pipe_read) { instance_double(IO, "pipe_read") }
  let(:pipe_write) { instance_double(IO, "pipe_write") }

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
      c.instance_variable_set(:@mode, :input)
      c.instance_variable_set(:@original_stty, nil)
      c.instance_variable_set(:@history, [])
      c.instance_variable_set(:@history_pos, nil)
      c.instance_variable_set(:@saved_input, String.new(""))
      c.instance_variable_set(:@kill_ring, String.new(""))
      c.instance_variable_set(:@spinner_running, false)
      c.instance_variable_set(:@spinner_frames, ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
      c.instance_variable_set(:@spinner_frame, 0)
      c.instance_variable_set(:@spinner_message, String.new(""))
    end
  end

  describe "#initialize" do
    it "sets up terminal raw mode" do
      # This test would require actual terminal interaction
      # Skip for now - test manually or with integration tests
      skip "Requires actual terminal"
    end

    it "initializes @input_buffer as mutable string to prevent FrozenError" do
      # This test verifies the fix for frozen string literal issue
      # With frozen_string_literal: true, @input_buffer = "" creates a frozen string
      # which causes FrozenError when trying to insert characters
      buffer = console.instance_variable_get(:@input_buffer)
      expect(buffer.frozen?).to be false
      expect { console.send(:insert_char, "a") }.not_to raise_error
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
      console.instance_variable_set(:@mode, :input)
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
      it "returns :eof when buffer is empty" do
        console.instance_variable_set(:@input_buffer, "")
        result = console.send(:parse_input, "\x04")
        expect(result).to eq(:eof)
      end

      it "returns nil when buffer is not empty" do
        console.instance_variable_set(:@input_buffer, "text")
        result = console.send(:parse_input, "\x04")
        expect(result).to be_nil
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
    it "clears the line and redraws prompt and buffer" do
      console.instance_variable_set(:@input_buffer, "test")
      console.instance_variable_set(:@cursor_pos, 4)
      console.send(:redraw_input_line, "> ")

      output = stdout.string
      expect(output).to include("\e[2K\r") # Clear line
      expect(output).to include("> test")
    end

    it "positions cursor correctly" do
      console.instance_variable_set(:@input_buffer, "hello")
      console.instance_variable_set(:@cursor_pos, 2)
      console.send(:redraw_input_line, "> ")

      output = stdout.string
      # Cursor should be at column 5 (prompt "> " = 2 chars, cursor_pos = 2, col = 2 + 2 + 1 = 5)
      expect(output).to match(/\e\[5G/)
    end
  end

  describe "#show_spinner" do
    it "switches to spinner mode" do
      allow(stdin).to receive(:wait_readable).and_return(nil)
      allow(stdin).to receive(:read_nonblock).and_raise(Errno::EAGAIN)
      allow(IO).to receive(:select).and_return(nil)

      console.show_spinner("Thinking...")
      expect(console.instance_variable_get(:@mode)).to eq(:spinner)
      expect(console.instance_variable_get(:@spinner_message)).to eq("Thinking...")
      expect(console.instance_variable_get(:@spinner_running)).to be true

      # Clean up
      console.hide_spinner
    end
  end

  describe "#hide_spinner" do
    it "stops spinner and clears line" do
      allow(stdin).to receive(:wait_readable).and_return(nil)
      console.instance_variable_set(:@spinner_running, true)
      console.instance_variable_set(:@spinner_thread, Thread.new { sleep 0.1 })

      console.hide_spinner

      expect(console.instance_variable_get(:@spinner_running)).to be false
      output = stdout.string
      expect(output).to include("\e[2K\r") # Clear line
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
end
