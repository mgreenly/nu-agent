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
      c.instance_variable_set(:@input_buffer, "")
      c.instance_variable_set(:@cursor_pos, 0)
      c.instance_variable_set(:@mode, :input)
      c.instance_variable_set(:@original_stty, nil)
      c.instance_variable_set(:@history, [])
      c.instance_variable_set(:@history_pos, nil)
      c.instance_variable_set(:@saved_input, "")
      c.instance_variable_set(:@kill_ring, "")
      c.instance_variable_set(:@spinner_running, false)
      c.instance_variable_set(:@spinner_frames, ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
      c.instance_variable_set(:@spinner_frame, 0)
      c.instance_variable_set(:@spinner_message, "")
    end
  end

  describe "#initialize" do
    it "sets up terminal raw mode" do
      # This test would require actual terminal interaction
      # Skip for now - test manually or with integration tests
      skip "Requires actual terminal"
    end
  end

  describe "#puts" do
    it "adds text to output queue" do
      console.puts("Hello, world!")
      queue = console.instance_variable_get(:@output_queue)
      expect(queue.pop).to eq("Hello, world!")
    end

    it "signals the output pipe" do
      expect(pipe_write).to receive(:write).with("x")
      console.puts("Test message")
    end

    it "handles multiple concurrent puts calls safely" do
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
      allow(pipe_read).to receive(:read_nonblock).and_raise(IO::WaitReadable)
    end

    it "returns empty array when queue is empty" do
      result = console.send(:drain_output_queue)
      expect(result).to eq([])
    end

    it "drains all queued messages" do
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
        console.instance_variable_set(:@input_buffer, "hello")
        console.instance_variable_set(:@cursor_pos, 5)
        console.send(:parse_input, "\x7F")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hell")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(4)
      end

      it "does nothing when cursor is at start" do
        console.instance_variable_set(:@input_buffer, "hello")
        console.instance_variable_set(:@cursor_pos, 0)
        console.send(:parse_input, "\x7F")
        expect(console.instance_variable_get(:@input_buffer)).to eq("hello")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(0)
      end
    end

    context "with printable characters" do
      it "inserts character at end" do
        console.instance_variable_set(:@input_buffer, "")
        console.instance_variable_set(:@cursor_pos, 0)
        console.send(:parse_input, "a")
        expect(console.instance_variable_get(:@input_buffer)).to eq("a")
        expect(console.instance_variable_get(:@cursor_pos)).to eq(1)
      end

      it "inserts multiple characters" do
        console.instance_variable_set(:@input_buffer, "")
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
      # Cursor should be at column 4 (prompt ">" + space = 2, cursor_pos = 2, total = 4)
      expect(output).to match(/\e\[4G/)
    end
  end

  describe "#show_spinner" do
    it "switches to spinner mode" do
      allow(stdin).to receive(:read_nonblock).and_raise(IO::WaitReadable)
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
      console.instance_variable_set(:@spinner_running, true)
      console.instance_variable_set(:@spinner_thread, Thread.new { sleep })

      console.hide_spinner

      expect(console.instance_variable_get(:@spinner_running)).to be false
      output = stdout.string
      expect(output).to include("\e[2K\r") # Clear line
    end
  end

  describe "#handle_output_for_input_mode" do
    before do
      allow(pipe_read).to receive(:read_nonblock).and_raise(IO::WaitReadable)
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
      allow(pipe_read).to receive(:read_nonblock).and_raise(IO::WaitReadable)

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
end
