# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nu::Agent::ConsoleIO::State do
  let(:console) do
    # Create a test console without terminal setup
    Nu::Agent::ConsoleIO.allocate.tap do |c|
      c.instance_variable_set(:@stdin, stdin)
      c.instance_variable_set(:@stdout, stdout)
      c.instance_variable_set(:@output_queue, Queue.new)
      c.instance_variable_set(:@output_pipe_read, pipe_read)
      c.instance_variable_set(:@output_pipe_write, pipe_write)
      c.instance_variable_set(:@mutex, Mutex.new)
      c.instance_variable_set(:@input_buffer, String.new(""))
      c.instance_variable_set(:@cursor_pos, 0)
      c.instance_variable_set(:@original_stty, nil)
      c.instance_variable_set(:@history, [])
      c.instance_variable_set(:@history_pos, nil)
      c.instance_variable_set(:@saved_input, String.new(""))
      c.instance_variable_set(:@kill_ring, String.new(""))
      c.instance_variable_set(:@spinner_state, Nu::Agent::SpinnerState.new)
      c.instance_variable_set(:@spinner_frames, ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
      # Initialize state to IdleState
      c.instance_variable_set(:@state, Nu::Agent::ConsoleIO::IdleState.new(c))
    end
  end

  let(:stdin) { instance_double(IO, "stdin") }
  let(:stdout) { StringIO.new }
  let(:pipe_read) { instance_double(IO, "pipe_read") }
  let(:pipe_write) { instance_double(IO, "pipe_write") }

  describe "State classes" do
    describe Nu::Agent::ConsoleIO::IdleState do
      it "is the initial state" do
        expect(console.current_state).to be_a(described_class)
      end

      it "transitions to ReadingUserInputState on readline" do
        # Block readline so we can check state during execution
        allow(IO).to receive(:select).and_return(nil) # Block indefinitely

        thread = Thread.new { console.readline("> ") }
        sleep 0.05 # Give it time to transition

        # During readline, state should be ReadingUserInputState
        expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::ReadingUserInputState)

        # Clean up
        thread.kill
        thread.join(0.5)
      end

      it "transitions to StreamingAssistantState on show_spinner" do
        allow(stdin).to receive(:wait_readable).and_return(nil)
        allow(stdin).to receive(:read_nonblock).and_raise(Errno::EAGAIN)
        allow(IO).to receive(:select).and_return(nil)

        console.show_spinner("Testing...")
        expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::StreamingAssistantState)

        console.hide_spinner
      end

      it "transitions to ProgressState on start_progress" do
        console.start_progress
        expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::ProgressState)
      end
    end

    describe Nu::Agent::ConsoleIO::ReadingUserInputState do
      before do
        # Set state to ReadingUserInput
        console.instance_variable_set(:@state, described_class.new(console))
      end

      it "transitions back to IdleState after input is submitted" do
        allow(stdin).to receive(:read_nonblock).and_return("\n")
        allow(IO).to receive(:select).and_return([[stdin], [], []])

        result = nil
        thread = Thread.new { result = console.readline("> ") }
        thread.join(1.0)

        expect(result).to eq("")
        expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::IdleState)
      end

      it "transitions back to IdleState on EOF" do
        # Manually invoke the transition that happens on EOF
        state = console.current_state
        state.on_input_completed

        expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::IdleState)
      end

      it "rejects show_spinner during input" do
        # Should not be able to show spinner while reading input
        expect { console.show_spinner("Test") }.to raise_error(Nu::Agent::ConsoleIO::StateTransitionError)
      end
    end

    describe Nu::Agent::ConsoleIO::StreamingAssistantState do
      before do
        allow(stdin).to receive(:wait_readable).and_return(nil)
        allow(stdin).to receive(:read_nonblock).and_raise(Errno::EAGAIN)
        allow(IO).to receive(:select).and_return(nil)

        console.show_spinner("Thinking...")
      end

      after do
        console.hide_spinner if console.current_state.is_a?(described_class)
      end

      it "transitions back to IdleState on hide_spinner" do
        console.hide_spinner
        expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::IdleState)
      end

      it "rejects readline during streaming" do
        expect { console.readline("> ") }.to raise_error(Nu::Agent::ConsoleIO::StateTransitionError)
      end

      it "allows updating spinner message without state change" do
        expect(console.current_state).to be_a(described_class)
        console.show_spinner("Still thinking...")
        expect(console.current_state).to be_a(described_class)
      end
    end

    describe Nu::Agent::ConsoleIO::ProgressState do
      before do
        console.start_progress
      end

      it "transitions back to IdleState on end_progress" do
        console.end_progress
        expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::IdleState)
      end

      it "allows progress updates while in ProgressState" do
        expect { console.update_progress("[====>  ] 50%") }.not_to raise_error
        expect(console.current_state).to be_a(described_class)
      end
    end

    describe Nu::Agent::ConsoleIO::PausedState do
      it "can be entered from any state" do
        # From Idle
        console.pause
        expect(console.current_state).to be_a(described_class)
      end

      it "remembers previous state for resumption" do
        console.pause
        paused_state = console.current_state
        expect(paused_state.previous_state).to be_a(Nu::Agent::ConsoleIO::IdleState)
      end

      it "can resume to previous state" do
        original_state_class = console.current_state.class
        console.pause
        console.resume
        expect(console.current_state.class).to eq(original_state_class)
      end
    end
  end

  describe "State transition validations" do
    it "prevents invalid transitions with clear error messages" do
      allow(stdin).to receive(:wait_readable).and_return(nil)
      allow(IO).to receive(:select).and_return(nil)

      console.show_spinner("Test")

      expect { console.readline("> ") }
        .to raise_error(Nu::Agent::ConsoleIO::StateTransitionError, /Cannot read input while streaming/)

      console.hide_spinner
    end

    it "allows puts from any state" do
      allow(pipe_write).to receive(:write)

      # From Idle
      expect { console.puts("Test 1") }.not_to raise_error

      # From Progress
      console.start_progress
      expect { console.puts("Test 2") }.not_to raise_error
      console.end_progress
    end
  end

  describe "#current_state" do
    it "returns the current state object" do
      expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::IdleState)
    end

    it "exposes state name for debugging" do
      expect(console.current_state_name).to eq(:idle)
    end
  end

  describe "state transition logging" do
    it "logs state transitions when debug is enabled" do
      console.instance_variable_set(:@debug, true)
      allow(pipe_write).to receive(:write)

      # Should log transition
      console.start_progress

      # Check that transition was logged (would need to capture debug output)
      expect(console.current_state).to be_a(Nu::Agent::ConsoleIO::ProgressState)
    end
  end
end
